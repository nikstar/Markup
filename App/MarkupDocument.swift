import AppKit
import UniformTypeIdentifiers

final class MarkupDocument: NSDocument {
  let session: EditorSession
  var sourceName = "Untitled"
  private var committedFile: MarkupFile
  private var history = ImageEditHistory()
  private var imageDigest: String?
  private var pendingImage: Data?
  private var autosaveTimer: Timer?
  private var encodingTask: Task<Void, Never>?
  private var autosavePixels: (type: String, file: MarkupFile, data: Data)?
  private var renderedFile: MarkupFile { editor?.includingOpenCaption(in: committedFile) ?? committedFile }
  private var savedOpenCaption = false
  private var historyChanged = false
  private var restoring = false
  var newImageDirectory: URL?
  private var exportOptions: ExportOptions?
  var editor: EditorViewController? {
    windowControllers.first?.contentViewController as? EditorViewController
  }
  init(file: MarkupFile, preferences: UserDefaults = .standard) {
    committedFile = file
    session = EditorSession(file: file, preferences: preferences)
    super.init()
    fileType = UTType.png.identifier
    // The editor owns document undo and inline text owns typing undo. Account
    // for committed changes once, synchronously, including programmatic replays.
    hasUndoManager = false
    session.onCommit = { [weak self] previous, name in
      guard let self, !restoring else { return }
      committedFile = session.file
      historyChanged = true
      if session.undo.isUndoing { history.cursor -= 1 }
      else if session.undo.isRedoing { history.cursor += 1 }
      else { history.append(from: previous, to: session.file, name: name, limit: session.undo.levelsOfUndo) }
      updateChangeCount(session.undo.isUndoing ? .changeUndone : session.undo.isRedoing ? .changeRedone : .changeDone)
      scheduleImageSave()
    }
  }
  override convenience init() {
    // A minimal valid source; NSDocument uses this initializer for autosave recovery.
    let context = try! ImageCodec.context(width: 1, height: 1)
    let data = try! ImageCodec.encode(context.makeImage()!, type: .png)
    self.init(file: MarkupFile(source: data, width: 1, height: 1))
  }
  override class var autosavesInPlace: Bool { true }
  override class var autosavesDrafts: Bool { false }
  override var autosavingFileType: String? { fileURL == nil ? markupType : fileType }
  override var displayName: String! {
    get { fileURL?.deletingPathExtension().lastPathComponent ?? sourceName }
    set {}
  }
  static let imageTypes: [UTType] = [.png, .jpeg, .tiff]
  override class var writableTypes: [String] { imageTypes.map(\.identifier) + [markupType] }
  override class var readableTypes: [String] { writableTypes }
  override var savePanelShowsFileFormatsControl: Bool { true }

  // Only bind a single-frame file when we can write its actual format back.
  // Multipage TIFF and animated PNG open as new still images.
  convenience init(opening url: URL, preferences: UserDefaults = .standard) throws {
    let data = try Data(contentsOf: url)
    let type = UTType(filenameExtension: url.pathExtension)
    if url.pathExtension.lowercased() == "markup" {
      try self.init(file: JSONDecoder().decode(MarkupFile.self, from: data).validated(), preferences: preferences)
      fileType = markupType
    } else {
      try self.init(file: MarkupFile.importing(data), preferences: preferences)
      sourceName = url.deletingPathExtension().lastPathComponent
      newImageDirectory = url.deletingLastPathComponent()
      guard let type, Self.imageTypes.contains(type),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        CGImageSourceGetCount(source) == 1,
        CGImageSourceGetType(source) as String? == type.identifier
      else { return }
      fileType = type.identifier
      restoreImage(data, at: url)
    }
    fileURL = url
    fileModificationDate = try url.resourceValues(forKeys: [.contentModificationDateKey])
      .contentModificationDate
  }
  override func makeWindowControllers() {
    let vc = EditorViewController(session: session)
    let window = MarkupWindow.editor(vc, title: displayName)
    window.center()
    let controller = NSWindowController(window: window)
    addWindowController(controller)
    vc.onPendingTextChange = { [weak self] in self?.updateChangeCount($0 ? .changeDone : .changeUndone) }
    vc.onTextSnapshotChange = { [weak self] in
      guard let self else { return }
      if editor?.fileIncludingText != session.file || savedOpenCaption {
        if !hasUnautosavedChanges { updateChangeCount(.changeDone) }
        scheduleImageSave()
      }
    }
    vc.onSave = { [weak self] in self?.save(nil) }
    vc.onOpen = { (NSApp.delegate as? AppDelegate)?.openDocument(nil) }
    vc.onCapture = { (NSApp.delegate as? AppDelegate)?.capture(nil) }
  }
  override func checkAutosavingSafety() throws {
    // The user chose in-place image editing, including older screenshots and
    // Downloads. writeSafely verifies the exact file revision before replacing it.
    if imageDigest == nil { try super.checkAutosavingSafety() }
  }

  private func restoreImage(_ data: Data, at url: URL) {
    let digest = ImageEditArchive.digest(data)
    imageDigest = digest
    guard session.markupPreferences.keepsEditHistory,
          let archive = ImageEditArchive.load(image: url, digest: digest),
          let file = try? archive.file.validated() else { return }
    restoring = true
    defer { committedFile = session.file; restoring = false }
    // Registering the old undo groups is bookkeeping, not a new document edit.
    defer { updateChangeCount(.changeCleared) }
    do {
      try archive.history.restore(file, in: session)
      history = archive.history
    } catch { session.undo.removeAllActions(); session.file = file; history = ImageEditHistory() }
  }

  private func scheduleImageSave() {
    guard !restoring else { return }
    if fileURL == nil {
      do { try createBackingPNG() }
      catch { presentError(error); return }
    }
    cancelScheduledSave()
    let timer = Timer(timeInterval: 0.75, repeats: false) { [weak self] _ in self?.saveAfterPause() }
    RunLoop.main.add(timer, forMode: .common)
    autosaveTimer = timer
  }

  private func cancelScheduledSave() {
    autosaveTimer?.invalidate()
    encodingTask?.cancel()
    encodingTask = nil
    autosavePixels = nil
  }

  private func saveAfterPause() {
    do {
      guard hasUnautosavedChanges else { try persistCleanHistory(); return }
      guard let name = fileType, let type = UTType(name), Self.imageTypes.contains(type) else {
        requestAutosave()
        return
      }
      // Snapshot the AppKit drawing on the main thread, then compress its immutable
      // pixels off the input path. A later edit cancels delivery of this generation.
      let renderer = editor?.canvas.renderer ?? MarkupRenderer()
      let file = renderedFile
      let image = try renderer.render(file, whiteBackground: type == .jpeg)
      encodingTask = Task.detached(priority: .utility) { [weak self] in
        guard !Task.isCancelled else { return }
        let result = Result { try ImageCodec.encode(image, type: type) }
        await MainActor.run { [weak self] in
          guard !Task.isCancelled, let self else { return }
          switch result {
          case let .success(bytes):
            autosavePixels = (name, file, bytes)
            requestAutosave()
          case let .failure(error): presentError(error)
          }
        }
      }
    } catch { presentError(error) }
  }

  private func requestAutosave() {
    autosave(withImplicitCancellability: true) { [weak self] error in
      if let error, (error as NSError).code != NSUserCancelledError { self?.presentError(error) }
    }
  }

  private func createBackingPNG() throws {
    let configured = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")?["location"] as? String
    let directory = newImageDirectory ?? configured.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
      ?? URL.desktopDirectory
    let cleanName = sourceName.replacingOccurrences(of: "/", with: "-")
    let name = String(decoding: cleanName.utf8.prefix(220), as: UTF8.self)
    let stem = name.isEmpty || name.hasPrefix(".") ? "Screenshot" : name
    let stage = directory.appendingPathComponent(".Markup-\(UUID().uuidString).png")
    try session.file.source.write(to: stage, options: .atomic)
    defer { try? FileManager.default.removeItem(at: stage) }
    var number = 1
    while true {
      let url = directory.appendingPathComponent((number == 1 ? stem : "\(stem) \(number)") + ".png")
      do { try FileManager.default.moveItem(at: stage, to: url) }
      catch let error as CocoaError where error.code == .fileWriteFileExists { number += 1; continue }
      fileURL = url
      fileType = UTType.png.identifier
      imageDigest = ImageEditArchive.digest(session.file.source)
      fileModificationDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
      return
    }
  }

  // Undo can return to the saved pixels before autosave fires. The new redo
  // entries still belong to that image even though AppKit considers it clean.
  private func persistCleanHistory() throws {
    guard historyChanged, !hasUnautosavedChanges, let url = fileURL, let digest = imageDigest,
          ImageEditArchive.digest(try Data(contentsOf: url)) == digest else { return }
    let bucket = ImageEditArchive.bucket(for: url)
    if session.markupPreferences.keepsEditHistory {
      let record = try ImageEditArchive(file: committedFile, history: history).stage(bucket: bucket, digest: digest)
      ImageEditArchive.didSave(record, bucket: bucket, image: url)
    } else {
      try ImageEditArchive.discard(for: url)
    }
    historyChanged = false
  }

  override func close() {
    cancelScheduledSave()
    do { try persistCleanHistory() } catch { presentError(error) }
    super.close()
  }

  override func writeSafely(to url: URL, ofType typeName: String, for operation: NSDocument.SaveOperationType) throws {
    guard Self.imageTypes.contains(where: { $0.identifier == typeName }) else {
      try super.writeSafely(to: url, ofType: typeName, for: operation)
      return
    }
    if operation == .autosaveInPlaceOperation || operation == .saveOperation, let imageDigest,
       ImageEditArchive.digest(try Data(contentsOf: url)) != imageDigest {
      throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey:
        "The image changed in another app. Reopen it or use Save As to keep your edits separately."])
    }
    let file = renderedFile
    let pixels: Data
    if let cached = autosavePixels, cached.type == typeName, cached.file == file { pixels = cached.data }
    else { pixels = try encode(file, ofType: typeName) }
    let digest = ImageEditArchive.digest(pixels)
    let bucket = ImageEditArchive.bucket(for: url)
    // Stage the matching history before AppKit atomically replaces the image.
    // If replacement fails, the previously saved pixels still select their own history.
    let record: URL?
    if session.markupPreferences.keepsEditHistory {
      var savedHistory = history
      if file != committedFile {
        savedHistory.append(from: committedFile, to: file, name: "Edit Text", limit: session.undo.levelsOfUndo)
      }
      record = try ImageEditArchive(file: file, history: savedHistory).stage(bucket: bucket, digest: digest)
    } else {
      record = nil
    }
    pendingImage = pixels
    defer { pendingImage = nil; autosavePixels = nil }
    try super.writeSafely(to: url, ofType: typeName, for: operation)
    if operation != .saveToOperation {
      imageDigest = digest
      historyChanged = false
      savedOpenCaption = file != committedFile
    }
    if let record {
      ImageEditArchive.didSave(record, bucket: bucket, image: url)
    } else {
      try ImageEditArchive.discard(for: url)
    }
  }

  override func read(from url: URL, ofType typeName: String) throws {
    let data = try Data(contentsOf: url)
    try read(from: data, ofType: typeName)
    if Self.imageTypes.contains(where: { $0.identifier == typeName }) { restoreImage(data, at: url) }
  }

  override func save(_ sender: Any?) {
    editor?.finishText()
    guard let url = fileURL, let type = fileType else { super.save(sender); return }
    save(to: url, ofType: type, for: .saveOperation) { [weak self] error in
      if let error { self?.presentError(error) }
    }
  }
  override func saveAs(_ sender: Any?) {
    editor?.finishText()
    super.saveAs(sender)
  }
  override func data(ofType typeName: String) throws -> Data {
    if let pendingImage, Self.imageTypes.contains(where: { $0.identifier == typeName }) { return pendingImage }
    return try encode(editor?.fileIncludingText ?? session.file, ofType: typeName)
  }
  private func encode(_ file: MarkupFile, ofType typeName: String) throws -> Data {
    if typeName == markupType {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(file)
    }
    guard let type = UTType(typeName) else { throw CocoaError(.fileWriteUnsupportedScheme) }
    let renderer = editor?.canvas.renderer ?? MarkupRenderer()
    if type == .pdf { return try renderer.pdf(file) }
    guard Self.imageTypes.contains(type) else { throw CocoaError(.fileWriteUnknown) }
    return try ImageCodec.encode(
      renderer.render(file, whiteBackground: type == .jpeg), type: type)
  }
  override func read(from data: Data, ofType typeName: String) throws {
    editor?.finishText(apply: false)
    cancelScheduledSave()
    session.file =
      typeName == markupType
      ? try JSONDecoder().decode(MarkupFile.self, from: data).validated()
      : try MarkupFile.importing(data)
    committedFile = session.file
    session.selectedID = nil
    session.undo.removeAllActions()
    history = ImageEditHistory()
    historyChanged = false
    savedOpenCaption = false
    imageDigest = nil
  }
  func saveProjectCopy() {
    guard let window = windowControllers.first?.window else { return }
    let panel = NSSavePanel()
    panel.title = "Save Editable Project Copy"
    panel.allowedContentTypes = [UTType(importedAs: markupType)]
    panel.nameFieldStringValue = displayName + ".markup"
    panel.beginSheetModal(for: window) { [weak self] result in
      guard let self, result == .OK, let url = panel.url else { return }
      do {
        try self.data(ofType: markupType).write(to: url, options: .atomic)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
      } catch { self.presentError(error) }
    }
  }
  func exportImage() {
    guard let window = windowControllers.first?.window else { return }
    let panel = NSSavePanel()
    panel.title = "Export image"
    panel.nameFieldStringValue = displayName + "-marked.png"
    panel.allowedContentTypes = [.png]
    panel.canCreateDirectories = true
    let options = ExportOptions(panel: panel)
    exportOptions = options
    panel.accessoryView = options.view
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      do {
        let data = try self.data(ofType: options.type.identifier)
        try data.write(to: url, options: .atomic)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
      } catch { self.presentError(error) }
      self.exportOptions = nil
    }
  }
}

private final class ExportOptions: NSObject {
  let popup = NSPopUpButton(frame: NSRect(x: 76, y: 0, width: 220, height: 28))
  let view = NSView(frame: NSRect(x: 0, y: 0, width: 310, height: 30))
  weak var panel: NSSavePanel?
  let types: [UTType] = [.png, .jpeg, .tiff, .pdf]
  var type: UTType { types[popup.indexOfSelectedItem] }
  init(panel: NSSavePanel) {
    self.panel = panel
    super.init()
    let label = NSTextField(labelWithString: "Format:")
    label.frame = NSRect(x: 0, y: 4, width: 70, height: 22)
    view.addSubview(label)
    popup.addItems(withTitles: [
      "PNG · lossless", "JPEG · white background", "TIFF · lossless", "PDF",
    ])
    popup.target = self
    popup.action = #selector(change)
    view.addSubview(popup)
  }
  @objc func change() {
    panel?.allowedContentTypes = [type]
    if let name = panel?.nameFieldStringValue {
      panel?.nameFieldStringValue =
        (name as NSString).deletingPathExtension + "." + (type.preferredFilenameExtension ?? "png")
    }
  }
}
