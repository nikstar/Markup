import AppKit
import UniformTypeIdentifiers

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var welcome: NSWindow?
  @MainActor private lazy var settings = SettingsWindowController()
  private var statusItem: NSStatusItem?
  private var statusDrop: ImageDropTarget?
  private var screenshotDrop: ScreenshotDropMonitor?
  private var captureProcess: Process?
  private static var isTestHost: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
  }
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(isTestHost ? .prohibited : .accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !Self.isTestHost else { return }
    installMenu()
    NSApp.servicesProvider = self
    if !ProcessInfo.processInfo.arguments.contains("--ui-test") { NSUpdateDynamicServices() }
    if !ProcessInfo.processInfo.arguments.contains("--ui-test") { installStatusItem() }
    // The open-application event is available during didFinishLaunching.
    if Self.launchesInBackground(arguments: ProcessInfo.processInfo.arguments,
                                 event: NSAppleEventManager.shared().currentAppleEvent) { return }
    if ProcessInfo.processInfo.arguments.contains("--ui-test")
      || ProcessInfo.processInfo.arguments.contains("--demo")
    {
      do { show(file: try SampleImage.file(), name: "Test screenshot") } catch {
        NSApp.presentError(error)
      }
    } else if NSDocumentController.shared.documents.isEmpty {
      showWelcome()
    }
  }
  static func launchesInBackground(arguments: [String], event: NSAppleEventDescriptor?) -> Bool {
    arguments.contains("--background") || (event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem)
  }

  private func prepareForInteraction() {
    if NSApp.activationPolicy() == .accessory { NSApp.setActivationPolicy(.regular) }
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !NSApp.windows.contains(where: { $0.level == .normal && $0.isVisible }) { showWelcome() }
    return true
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { openURL(url) }
  }
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for file in filenames { openURL(URL(fileURLWithPath: file)) }
    sender.reply(toOpenOrPrint: .success)
  }
  var current: MarkupDocument? {
    NSDocumentController.shared.documents.compactMap { $0 as? MarkupDocument }.first {
      $0.windowControllers.contains {
        $0.window?.isMainWindow == true || $0.window?.isKeyWindow == true
      }
    }
  }
  func show(file: MarkupFile, name: String) {
    let document = MarkupDocument(file: file)
    document.sourceName = name
    show(document)
  }
  private func show(_ document: MarkupDocument) {
    prepareForInteraction()
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    welcome?.orderOut(nil)
  }
  func openURL(_ url: URL) {
    do {
      if let document = NSDocumentController.shared.documents.first(where: { $0.fileURL == url }) {
        prepareForInteraction()
        document.showWindows()
        welcome?.orderOut(nil)
        return
      }
      try show(MarkupDocument(opening: url))
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
    } catch { NSApp.presentError(error) }
  }
  @objc func openDocument(_ sender: Any?) {
    prepareForInteraction()
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image, UTType(importedAs: markupType)]
    panel.allowsMultipleSelection = true
    panel.begin { [weak self] response in
      if response == .OK { for url in panel.urls { self?.openURL(url) } }
    }
  }
  @objc func newDocument(_ sender: Any?) { showWelcome() }
  @objc func newFromClipboard(_ sender: Any?) {
    prepareForInteraction()
    if let data = ImageCodec.pasteboardImage(.general) {
      do { show(file: try MarkupFile.importing(data), name: "Clipboard") } catch {
        NSApp.presentError(error)
      }
    } else if let urls = NSPasteboard.general.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    {
      for url in urls { openURL(url) }
    } else {
      let alert = NSAlert()
      alert.messageText = "Copy an image first"
      alert.informativeText =
        "Copy a screenshot, an image, or an image file, then choose New from Clipboard."
      alert.runModal()
    }
  }
  @objc func blankCanvas(_ sender: Any?) {
    do {
      let context = try ImageCodec.context(width: 1600, height: 1000)
      context.setFillColor(NSColor.white.cgColor)
      context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1000))
      show(
        file: try MarkupFile.importing(ImageCodec.encode(context.makeImage()!, type: .png)),
        name: "Blank canvas")
    } catch { NSApp.presentError(error) }
  }
  @objc func capture(_ sender: Any?) {
    guard captureProcess == nil else { return }
    // The system capture picker provides region/window selection and the OS permission flow.
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Markup-\(UUID().uuidString).png")
    let windows = NSApp.windows.filter { $0.isVisible && $0.level == .normal }
    windows.forEach { $0.orderOut(nil) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-i", "-x", url.path]
    captureProcess = process
    process.terminationHandler = { [weak self] process in
      DispatchQueue.main.async {
        defer {
          try? FileManager.default.removeItem(at: url)
          self?.captureProcess = nil
        }
        windows.forEach { $0.orderFront(nil) }
        if FileManager.default.fileExists(atPath: url.path) {
          do {
            try self?.show(file: MarkupFile.importing(Data(contentsOf: url)), name: "Screenshot")
          } catch { NSApp.presentError(error) }
        } else if process.terminationStatus != 0 {
          // Escape also exits with a nonzero status; don't turn cancellation into an error dialog.
          NSApp.activate(ignoringOtherApps: true)
        }
      }
    }
    do { try process.run() } catch {
      captureProcess = nil
      windows.forEach { $0.orderFront(nil) }
      NSApp.presentError(error)
    }
  }
  @objc func markupImage(
    _ pasteboard: NSPasteboard, userData: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    if let urls = pasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
    {
      for url in urls { openURL(url) }
      return
    }
    if let data = ImageCodec.pasteboardImage(pasteboard) {
      do { show(file: try MarkupFile.importing(data), name: "Image") } catch let problem {
        error.pointee = problem.localizedDescription as NSString
      }
    } else {
      error.pointee = "No image was provided to Markup."
    }
  }
  @objc func saveProjectCopy(_ sender: Any?) { current?.saveProjectCopy() }
  @objc func exportImage(_ sender: Any?) { current?.exportImage() }
  @objc func copyImage(_ sender: Any?) { current?.editor?.copyImage() }
  @objc func undoEdit(_ sender: Any?) {
    current?.editor?.undoEdit()
  }
  @objc func redoEdit(_ sender: Any?) {
    current?.editor?.redoEdit()
  }
  @objc func deleteObject(_ sender: Any?) { current?.editor?.deleteObject() }
  @objc func duplicateObject(_ sender: Any?) { current?.editor?.duplicateObject() }
  @objc func importSticker(_ sender: Any?) { current?.editor?.importSticker() }
  @objc func clearAnnotations(_ sender: Any?) { current?.editor?.clearAnnotations() }
  @MainActor @objc func showSettings(_ sender: Any?) {
    prepareForInteraction()
    settings.showWindow(sender)
  }
  @objc func about(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: "Markup", .applicationVersion: "1.0",
      .credits: NSAttributedString(
        string:
          "Independent AppKit screenshot editor.\nDrawing geometry adapted from Telegram iOS.\nGNU GPL v2 or later. No Telegram account required."
      ),
    ])
  }
  func installMenu() {
    let main = NSMenu()
    func menu(_ title: String) -> NSMenu {
      let item = NSMenuItem()
      item.title = title
      let m = NSMenu(title: title)
      item.submenu = m
      main.addItem(item)
      return m
    }
    @discardableResult func item(
      _ m: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
      _ modifiers: NSEvent.ModifierFlags = .command, _ target: AnyObject? = nil
    ) -> NSMenuItem {
      let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
      i.keyEquivalentModifierMask = modifiers
      i.target = target
      m.addItem(i)
      return i
    }
    let app = menu("Markup")
    item(app, "About Markup", #selector(about), "", .command, self)
    app.addItem(.separator())
    item(app, "Settings…", #selector(showSettings), ",", .command, self)
    app.addItem(.separator())
    let services = NSMenu(title: "Services")
    let si = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    si.submenu = services
    app.addItem(si)
    NSApp.servicesMenu = services
    app.addItem(.separator())
    item(app, "Hide Markup", #selector(NSApplication.hide(_:)), "h")
    item(app, "Quit Markup", #selector(NSApplication.terminate(_:)), "q")
    let file = menu("File")
    item(file, "New…", #selector(newDocument), "n", .command, self)
    item(file, "New from Clipboard", #selector(newFromClipboard), "n", [.command, .shift], self)
    item(file, "New Blank Canvas", #selector(blankCanvas), "n", [.command, .option], self)
    item(file, "Open…", #selector(openDocument), "o", .command, self)
    item(file, "Capture Screenshot…", #selector(capture), "2", [.command, .shift], self)
    file.addItem(.separator())
    item(file, "Save", #selector(NSDocument.save(_:)), "s")
    item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
    item(file, "Save Editable Project Copy…", #selector(saveProjectCopy), "", [], self)
    item(file, "Export Image…", #selector(exportImage), "e", [.command, .shift], self)
    item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
    let edit = menu("Edit")
    item(edit, "Undo", #selector(undoEdit), "z", .command, self)
    item(edit, "Redo", #selector(redoEdit), "z", [.command, .shift], self)
    edit.addItem(.separator())
    item(edit, "Cut", #selector(NSText.cut(_:)), "x")
    item(edit, "Copy Edited Image", #selector(copyImage), "c", .command, self)
    item(edit, "Paste", #selector(NSText.paste(_:)), "v")
    item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
    let previousCopyShortcut = item(edit, "Copy Edited Image", #selector(copyImage), "c", [.command, .shift], self)
    previousCopyShortcut.isHidden = true
    previousCopyShortcut.allowsKeyEquivalentWhenHidden = true
    item(edit, "Copy Selected Text", #selector(NSText.copy(_:)), "", [], nil)
    item(edit, "Duplicate Object", #selector(duplicateObject), "d", .command, self)
    item(edit, "Delete Object", #selector(deleteObject), "", .command, self)
    item(edit, "Import Sticker…", #selector(importSticker), "i", [.command, .shift], self)
    item(edit, "Clear Annotations", #selector(clearAnnotations), "", .command, self)
    let view = menu("View")
    item(view, "Zoom In", #selector(zoomIn), "+", .command, self)
    item(view, "Zoom Out", #selector(zoomOut), "-", .command, self)
    item(view, "Actual Pixels", #selector(actualPixels), "1", .command, self)
    item(view, "Fit to Window", #selector(fitImage), "0", .command, self)
    let window = menu("Window")
    item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
    item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
    NSApp.windowsMenu = window
    NSApp.mainMenu = main
  }
  @objc private func zoomIn() { changeZoom(by: 1.25) }
  @objc private func zoomOut() { changeZoom(by: 1 / 1.25) }
  private func changeZoom(by factor: CGFloat) {
    guard let canvas = current?.editor?.canvas else { return }
    canvas.setZoom(canvas.zoom * factor, at: canvas.editingBounds.center)
  }
  @objc private func actualPixels() { current?.editor?.canvas.actualSize() }
  @objc private func fitImage() { current?.editor?.canvas.fit() }
  private var imageDrop: ImageDrop {
    ImageDrop(file: { [weak self] in self?.openURL($0) }, image: { [weak self] data, name in
      do { self?.show(file: try MarkupFile.importing(data), name: name) }
      catch { NSApp.presentError(error) }
    })
  }

  private func installStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.image = NSImage(
      systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Markup")
    let menu = NSMenu()
    for (title, selector) in [
      ("Capture Screenshot…", #selector(capture)),
      ("New from Clipboard", #selector(newFromClipboard)), ("Open Image…", #selector(openDocument)),
    ] {
      let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    settingsItem.target = self
    let quit = menu.addItem(withTitle: "Quit Markup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    statusItem?.menu = menu
    if let item = statusItem {
      item.button?.toolTip = "Markup • Drop an image to edit"
      statusDrop = ImageDropTarget.install(on: item, drop: imageDrop)
    }
    screenshotDrop = ScreenshotDropMonitor(drop: imageDrop)
    screenshotDrop?.start()
  }
  private func showWelcome() {
    prepareForInteraction()
    if welcome == nil {
      welcome = MarkupWindow.welcome(
        open: { [weak self] in self?.openDocument(nil) },
        files: imageDrop.file, image: imageDrop.image)
    }
    welcome?.makeKeyAndOrderFront(nil)
  }
}
