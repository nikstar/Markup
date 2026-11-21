import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Markup

@MainActor
final class AutosaveTests: XCTestCase {
  private func waitForPixels(_ data: Data, at url: URL, line: UInt = #line) {
    let deadline = Date(timeIntervalSinceNow: 5)
    while (try? Data(contentsOf: url)) != data, Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
    }
    XCTAssertTrue((try? Data(contentsOf: url)) == data, "Expected automatic image write", line: line)
  }

  func testAutosaveRestoresOriginalLayersUndoRedoAndNewBranch() throws {
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let url = directory.url.appendingPathComponent("Image.png")
    let original = try SampleImage.file()
    try original.source.write(to: url)
    let first = try MarkupDocument(opening: url)
    let box = Annotation(tool: .rectangle, rect: CGRect(x: 30, y: 40, width: 120, height: 80))
    first.session.add(box)
    var cropped = first.session.file
    cropped.crop = CGRect(x: 10, y: 10, width: 320, height: 200)
    first.session.commit(cropped, name: "Crop")
    waitForPixels(try first.data(ofType: UTType.png.identifier), at: url)
    first.session.undo.undo()
    waitForPixels(try first.data(ofType: UTType.png.identifier), at: url)
    first.close()
    let doc = try MarkupDocument(opening: url)
    XCTAssertEqual(doc.session.file.annotations, [box])
    XCTAssertEqual(doc.session.file.source, original.source)
    XCTAssertNil(doc.session.file.crop)
    XCTAssertEqual(doc.session.undo.undoActionName, "Add Rectangle")
    XCTAssertEqual(doc.session.undo.redoActionName, "Crop")
    doc.session.undo.redo()
    XCTAssertEqual(doc.session.file, cropped)
    doc.session.undo.undo()
    doc.session.undo.undo()
    XCTAssertEqual(doc.session.file, original)
    doc.session.add(Annotation(tool: .fill))
    XCTAssertFalse(doc.session.undo.canRedo)
    waitForPixels(try doc.data(ofType: UTType.png.identifier), at: url)
    doc.close()
    let moved = directory.url.appendingPathComponent("Renamed.png")
    try FileManager.default.moveItem(at: url, to: moved)
    let renamed = try MarkupDocument(opening: moved)
    XCTAssertEqual(renamed.session.file.annotations.map(\.tool), [.fill])
    XCTAssertEqual(renamed.session.undo.undoActionName, "Add Fill")
    renamed.close()
  }

  func testWindowCloseBeforeDebounceFlushesLatestEdit() throws {
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let url = directory.url.appendingPathComponent("Closing.png")
    try SampleImage.file().source.write(to: url)
    let doc = try MarkupDocument(opening: url)
    NSDocumentController.shared.addDocument(doc)
    doc.makeWindowControllers()
    doc.session.add(Annotation(tool: .fill))
    let expected = try doc.data(ofType: UTType.png.identifier)
    let window = try XCTUnwrap(doc.windowControllers.first?.window)
    window.performClose(nil)
    waitForPixels(expected, at: url)
    XCTAssertNil(window.attachedSheet)
    let reopened = try MarkupDocument(opening: url)
    XCTAssertEqual(reopened.session.file.annotations.map(\.tool), [.fill])
    XCTAssertTrue(reopened.session.undo.canUndo)
    reopened.close()
    doc.close()
  }

  func testClosingOnOriginalPixelsRetainsRedo() throws {
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let url = directory.url.appendingPathComponent("Image.png")
    let original = try SampleImage.file()
    try original.source.write(to: url)
    let first = try MarkupDocument(opening: url)
    first.session.add(Annotation(tool: .fill))
    first.session.undo.undo()
    first.close()
    let doc = try MarkupDocument(opening: url)
    XCTAssertFalse(doc.session.undo.canUndo)
    XCTAssertEqual(doc.session.undo.redoActionName, "Add Fill")
    doc.session.undo.redo()
    XCTAssertEqual(doc.session.file.annotations.first?.tool, .fill)
    doc.close()
  }

  func testCopyShortcutTargetsImageEvenWithTextSelection() throws {
    let previousMenu = NSApp.mainMenu
    let previousServices = NSApp.servicesMenu
    let previousWindows = NSApp.windowsMenu
    defer { NSApp.mainMenu = previousMenu; NSApp.servicesMenu = previousServices; NSApp.windowsMenu = previousWindows }
    let app = AppDelegate()
    app.installMenu()
    let edit = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)
    let commandC = edit.items.filter { $0.keyEquivalent == "c" && $0.keyEquivalentModifierMask == .command }
    XCTAssertEqual(commandC.count, 1)
    XCTAssertEqual(commandC.first?.action, #selector(AppDelegate.copyImage(_:)))
    XCTAssertTrue(commandC.first?.target === app)
    XCTAssertEqual(edit.item(withTitle: "Copy Selected Text")?.action, #selector(NSText.copy(_:)))
  }

  func testExternalReplacementDoesNotRestoreOrOverwriteUnrelatedPixels() throws {
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let url = directory.url.appendingPathComponent("Image.png")
    let original = try SampleImage.file()
    try original.source.write(to: url)
    let doc = try MarkupDocument(opening: url)
    doc.session.add(Annotation(tool: .fill))
    waitForPixels(try doc.data(ofType: UTType.png.identifier), at: url)
    try original.source.write(to: url, options: .atomic)
    XCTAssertThrowsError(try doc.writeSafely(to: url, ofType: UTType.png.identifier, for: .autosaveInPlaceOperation))
    XCTAssertEqual(try Data(contentsOf: url), original.source)
    doc.close()
    let replacement = try MarkupDocument(opening: url)
    XCTAssertTrue(replacement.session.file.annotations.isEmpty)
    XCTAssertFalse(replacement.session.undo.canUndo)
    replacement.close()
  }

  func testScreenshotPromiseGetsUniqueBackingPNGOnFirstEdit() throws {
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let existing = directory.url.appendingPathComponent("Screenshot.png")
    try Data([0x42]).write(to: existing)
    let doc = MarkupDocument(file: try SampleImage.file())
    doc.newImageDirectory = directory.url
    doc.sourceName = "Screenshot"
    XCTAssertNil(doc.fileURL)
    doc.session.add(Annotation(tool: .fill))
    let url = try XCTUnwrap(doc.fileURL)
    XCTAssertEqual(url.lastPathComponent, "Screenshot 2.png")
    waitForPixels(try doc.data(ofType: UTType.png.identifier), at: url)
    XCTAssertEqual(try Data(contentsOf: existing), Data([0x42]))
    doc.close()
  }

  func testLiveCaptionAutosavesWithoutEndingTypingAndCancelRestoresImage() throws {
    let directory = try DropDirectory()
    defer { withExtendedLifetime(directory) {} }
    let url = directory.url.appendingPathComponent("Image.png")
    let original = try SampleImage.file()
    try original.source.write(to: url)
    let doc = try MarkupDocument(opening: url)
    doc.makeWindowControllers()
    let editor = try XCTUnwrap(doc.editor)
    editor.editText(at: original.imageBounds.center, annotation: nil)
    let text = try XCTUnwrap(editor.canvas.inlineText)
    text.insertText("Look", replacementRange: NSRange(location: NSNotFound, length: 0))
    waitForPixels(try doc.data(ofType: UTType.png.identifier), at: url)
    text.insertText(" here", replacementRange: NSRange(location: NSNotFound, length: 0))
    let expected = try doc.data(ofType: UTType.png.identifier)
    waitForPixels(expected, at: url)
    let restored = try MarkupDocument(opening: url)
    XCTAssertEqual(restored.session.file.annotations.first?.text, "Look here")
    XCTAssertTrue(restored.session.undo.canUndo)
    restored.close()
    let clipboard = NSPasteboard.withUniqueName()
    defer { clipboard.releaseGlobally() }
    XCTAssertNotNil(text.onCopyEditedImage)
    text.onCopyEditedImage = { editor.writeEditedImage(to: clipboard) }
    text.selectAll(nil)
    let copy = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
      timestamp: 0, windowNumber: try XCTUnwrap(text.window).windowNumber, context: nil,
      characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
    XCTAssertTrue(text.performKeyEquivalent(with: copy))
    XCTAssertEqual(clipboard.data(forType: .png), expected)
    XCTAssertTrue(editor.canvas.inlineText === text)
    text.cancelOperation(nil)
    waitForPixels(try doc.data(ofType: UTType.png.identifier), at: url)
    doc.close()
    let reopened = try MarkupDocument(opening: url)
    XCTAssertTrue(reopened.session.file.annotations.isEmpty)
    reopened.close()
  }
}
