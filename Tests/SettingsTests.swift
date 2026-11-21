import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Markup

@MainActor
final class SettingsTests: XCTestCase {
  private func defaults() -> UserDefaults {
    let suite = "MarkupTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    return defaults
  }

  func testDisablingHistoryBetweenEditsKeepsLiveUndoAndSavesFlatPNG() async throws {
    let defaults = defaults()
    let prefs = MarkupPreferences(defaults)
    XCTAssertTrue(prefs.keepsEditHistory)
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let url = directory.url.appendingPathComponent("Screenshot.png")
    try SampleImage.file().source.write(to: url)
    let doc = try MarkupDocument(opening: url, preferences: defaults)
    let box = Annotation(tool: .rectangle, rect: CGRect(x: 32, y: 48, width: 100, height: 60))
    doc.session.add(box)
    func save() async throws {
      try await doc.save(to: url, ofType: UTType.png.identifier, for: .saveOperation)
    }
    try await save()
    let digest = ImageEditArchive.digest(try Data(contentsOf: url))
    XCTAssertNotNil(ImageEditArchive.load(image: url, digest: digest))
    prefs.keepsEditHistory = false
    let flat = try MarkupDocument(opening: url, preferences: defaults)
    XCTAssertTrue(flat.session.file.annotations.isEmpty)
    flat.close()
    doc.session.add(Annotation(tool: .fill))
    doc.session.undo.undo()
    XCTAssertEqual(doc.session.file.annotations, [box])
    XCTAssertTrue(doc.session.undo.canRedo)
    try await save() // Identical pixels must also drop their prior archive.
    XCTAssertNil(ImageEditArchive.load(image: url, digest: digest))
    doc.session.undo.redo()
    let expected = try doc.data(ofType: UTType.png.identifier)
    let deadline = Date(timeIntervalSinceNow: 5)
    while (try Data(contentsOf: url)) != expected, Date() < deadline {
      try await Task.sleep(for: .milliseconds(30))
    }
    XCTAssertEqual(try Data(contentsOf: url), expected)
    doc.close()
    prefs.keepsEditHistory = true
    let reopened = try MarkupDocument(opening: url, preferences: defaults)
    XCTAssertTrue(reopened.session.file.annotations.isEmpty)
    XCTAssertFalse(reopened.session.undo.canUndo)
    reopened.close()
  }

  func testHistoryOffDoesNotSaveRedoForCleanPixels() throws {
    let defaults = defaults()
    MarkupPreferences(defaults).keepsEditHistory = false
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let url = directory.url.appendingPathComponent("Screenshot.png")
    let original = try SampleImage.file()
    try original.source.write(to: url)
    let doc = try MarkupDocument(opening: url, preferences: defaults)
    doc.session.add(Annotation(tool: .fill))
    doc.session.undo.undo()
    doc.close()
    XCTAssertNil(ImageEditArchive.load(image: url, digest: ImageEditArchive.digest(original.source)))
  }

  func testScrollEventDirectionUpdatesInOpenCanvasAndCommandStillZooms() throws {
    let defaults = defaults()
    let canvas = CanvasView(session: EditorSession(file: try SampleImage.file(), preferences: defaults))
    canvas.frame.size = CGSize(width: 600, height: 430)
    canvas.setZoom(2, at: canvas.bounds.center)
    let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                   wheel1: 14, wheel2: -9, wheel3: 0))
    let event = try XCTUnwrap(NSEvent(cgEvent: cg))
    XCTAssertFalse(MarkupPreferences(defaults).reversesScrollPan)
    let start = canvas.pan
    canvas.scrollWheel(with: event)
    XCTAssertEqual(canvas.pan, CGPoint(x: start.x + event.scrollingDeltaX, y: start.y + event.scrollingDeltaY))
    MarkupPreferences(defaults).reversesScrollPan = true
    canvas.scrollWheel(with: event)
    XCTAssertEqual(canvas.pan, start)
    let zoom = canvas.zoom
    cg.flags = .maskCommand
    canvas.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
    XCTAssertLessThan(canvas.zoom, zoom)
  }

  func testOnlyLoginItemAndExplicitBackgroundLaunchAreQuiet() {
    func event(_ id: AEEventID, _ reason: AEKeyword? = nil) -> NSAppleEventDescriptor {
      let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: id, targetDescriptor: nil,
                                         returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
      if let reason { event.setParam(NSAppleEventDescriptor(enumCode: reason), forKeyword: keyAEPropData) }
      return event
    }
    XCTAssertTrue(AppDelegate.launchesInBackground(arguments: [], event: event(kAEOpenApplication, keyAELaunchedAsLogInItem)))
    XCTAssertTrue(AppDelegate.launchesInBackground(arguments: ["--background"], event: nil))
    XCTAssertFalse(AppDelegate.launchesInBackground(arguments: [], event: nil))
    XCTAssertFalse(AppDelegate.launchesInBackground(arguments: [], event: event(kAEOpenApplication)))
    XCTAssertFalse(AppDelegate.launchesInBackground(arguments: [], event: event(kAEOpenDocuments, keyAELaunchedAsLogInItem)))
  }

  func testStandardSettingsMenuShortcut() throws {
    let oldMenu = NSApp.mainMenu, oldWindows = NSApp.windowsMenu, oldServices = NSApp.servicesMenu
    defer { NSApp.mainMenu = oldMenu; NSApp.windowsMenu = oldWindows; NSApp.servicesMenu = oldServices }
    let delegate = AppDelegate()
    delegate.installMenu()
    let item = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu?.item(withTitle: "Settings…"))
    XCTAssertEqual(item.keyEquivalent, ",")
    XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    XCTAssertEqual(item.action, #selector(AppDelegate.showSettings(_:)))
    XCTAssertTrue(item.target === delegate)
  }
}
