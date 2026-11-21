import AppKit
import XCTest

final class MarkupUITests: XCTestCase {
  var app: XCUIApplication!
  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--ui-test"]
    app.launch()
    app.activate()
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
  }
  override func tearDownWithError() throws { app.terminate() }
  var editor: XCUIElement { app.windows["Test screenshot"] }
  func canvas() -> XCUIElement { editor.descendants(matching: .any)["markupCanvas"].firstMatch }
  func count(_ n: Int) {
    let element = canvas()
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    XCTAssertTrue(element.value.debugDescription.contains("\(n) annotations"), element.debugDescription)
  }
  func draw(from: CGVector, to: CGVector) {
    app.activate()
    let c = canvas()
    c.coordinate(withNormalizedOffset: from).press(
      forDuration: 0.05, thenDragTo: c.coordinate(withNormalizedOffset: to))
  }
  func testDrawUndoRedoAndCopy() {
    XCTAssertTrue(editor.buttons["tool_pen"].exists)
    draw(from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.5))
    count(1)
    editor.buttons["undo"].click()
    count(0)
    editor.buttons["redo"].click()
    count(1)
    let before = NSPasteboard.general.changeCount
    editor.buttons["copyImage"].click()
    XCTAssertGreaterThan(NSPasteboard.general.changeCount, before)
    XCTAssertTrue(NSPasteboard.general.types?.contains(.png) == true)
  }
  func testShapeSelectionDuplicateDeleteAndText() {
    editor.buttons["addObject"].click()
    app.menuItems["Rectangle"].click()
    count(1)
    editor.buttons["Properties"].click()
    editor.buttons["duplicateObject"].click()
    count(2)
    editor.buttons["deleteObject"].click()
    count(1)
    editor.buttons["mode_text"].click()
    canvas().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).click()
    let text = app.textViews["textEntry"]
    XCTAssertTrue(text.waitForExistence(timeout: 3))
    text.click()
    text.typeText("Look here")
    app.buttons["applyText"].click()
    count(2)
    let attachment = XCTAttachment(screenshot: editor.screenshot())
    attachment.name = "Markup AppKit editor"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
