import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A drop may contain a different representation for each image. Screenshot supplies
/// a file promise, Finder supplies a file URL, and other apps can supply pixels directly.
struct ImageDrop {
  var file: (URL) -> Void
  var image: (Data, String) -> Void
  var failed: (Error) -> Void = { NSApp.presentError($0) }

  private static let imageTypes = (CGImageSourceCopyTypeIdentifiers() as! [String])
    .filter { UTType($0)?.conforms(to: .image) == true }.map(NSPasteboard.PasteboardType.init(rawValue:))
  static let types = [.fileURL] + imageTypes
    + NSFilePromiseReceiver.readableDraggedTypes.map(NSPasteboard.PasteboardType.init(rawValue:))

  private enum Item {
    case file(URL)
    case image(NSPasteboardItem, NSPasteboard.PasteboardType)
    case promise(NSFilePromiseReceiver)
  }

  private static func items(_ board: NSPasteboard) -> [Item] {
    let objects = board.readObjects(forClasses: [NSFilePromiseReceiver.self, NSPasteboardItem.self]) ?? []
    // The fallback reading class matches every item, preserving pasteboard order.
    // A single Finder item can offer both a real URL and a promise.
    let pasteboardItems = board.pasteboardItems ?? []
    return zip(pasteboardItems, objects).compactMap { item, object in
      if let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        if values?.isDirectory != true && (type?.conforms(to: .image) == true || url.pathExtension.lowercased() == "markup") {
          return .file(url)
        }
      }
      if let receiver = object as? NSFilePromiseReceiver,
         receiver.fileTypes.contains(where: { UTType($0)?.conforms(to: .image) == true }) {
        return .promise(receiver)
      }
      if let type = item.availableType(from: imageTypes) { return .image(item, type) }
      return nil
    }
  }

  static func operation(_ board: NSPasteboard, allowed: NSDragOperation) -> NSDragOperation {
    allowed.contains(.copy) && !items(board).isEmpty ? .copy : []
  }

  func open(_ board: NSPasteboard) -> Bool {
    var accepted = false
    var promises = [NSFilePromiseReceiver]()
    for item in Self.items(board) {
      switch item {
      case let .file(url):
        // Some Screenshot versions vend their private temporary URL as well.
        // Read it before the source finishes the drag and removes that file.
        if url.pathComponents.contains("TemporaryItems") && url.pathComponents.contains(where: {
          $0.lowercased().contains("screencaptureui")
        }) {
          do { image(try Data(contentsOf: url), url.deletingPathExtension().lastPathComponent) }
          catch { failed(error); continue }
        } else {
          file(url)
        }
      case let .image(item, type):
        guard let data = item.data(forType: type) else { continue }
        image(data, "Image")
      case let .promise(receiver):
        promises.append(receiver)
        continue
      }
      accepted = true
    }
    if !promises.isEmpty {
      do {
        try receive(promises)
        accepted = true
      } catch { failed(error) }
    }
    return accepted
  }

  func receive(_ promises: [NSFilePromiseReceiver]) throws {
    // AppKit requires all promises from one drag to use the same directory,
    // and requires the request itself to happen inside performDragOperation.
    let directory = try DropDirectory()
    for promise in promises {
      promise.receivePromisedFiles(atDestination: directory.url, options: [:],
                                   operationQueue: Self.readQueue) { url, error in
        let result = Result { () -> (Data, String) in
          if let error { throw error }
          return try directory.read(url)
        }
        DispatchQueue.main.async {
          switch result {
          case let .success((data, name)): image(data, name)
          case let .failure(error): failed(error)
          }
        }
      }
    }
  }

  private static let readQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "Markup image drops"
    queue.qualityOfService = .userInitiated
    return queue
  }()
}

/// The receiver retains the directory until all coordinated reads finish, including cancellations.
final class DropDirectory {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  init() throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                           attributes: [.posixPermissions: 0o700])
  }
  deinit { try? FileManager.default.removeItem(at: url) }
  func read(_ promised: URL) throws -> (Data, String) {
    guard promised.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path
      == url.resolvingSymlinksInPath().standardizedFileURL.path else { throw CocoaError(.fileReadInvalidFileName) }
    return (try Data(contentsOf: promised), promised.deletingPathExtension().lastPathComponent)
  }
}

/// Receives AppKit drag callbacks as a panel subview or the status item's window delegate.
final class ImageDropTarget: NSView, NSWindowDelegate {
  let drop: ImageDrop
  var highlight: (Bool) -> Void = { _ in }
  var didDrop: () -> Void = {}
  init(frame: CGRect = .zero, drop: ImageDrop) {
    self.drop = drop
    super.init(frame: frame)
    autoresizingMask = [.width, .height]
    registerForDraggedTypes(ImageDrop.types)
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { fatalError() }
  static func install(on item: NSStatusItem, drop: ImageDrop) -> ImageDropTarget? {
    guard let button = item.button, let window = button.window else { return nil }
    let target = ImageDropTarget(drop: drop)
    target.highlight = { [weak button] value in button?.highlight(value) }
    // NSStatusBarWindow forwards window-level drags to its delegate. Keep the
    // button itself untouched so AppKit continues to handle menu tracking.
    window.registerForDraggedTypes(ImageDrop.types)
    window.delegate = target
    return target
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let operation = ImageDrop.operation(sender.draggingPasteboard, allowed: sender.draggingSourceOperationMask)
    highlight(!operation.isEmpty)
    return operation
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { highlight(false) }
  override func draggingEnded(_ sender: NSDraggingInfo) { highlight(false) }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    highlight(false)
    guard drop.open(sender.draggingPasteboard) else { return false }
    didDrop()
    return true
  }
}
