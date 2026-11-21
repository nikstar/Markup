import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import Markup

final class InlineTextTests: XCTestCase {
  private func editor() throws -> (NSWindow, EditorViewController) {
    let vc = EditorViewController(session: EditorSession(file: try SampleImage.file()))
    let window = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 1040, height: 660),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.contentViewController = vc
    vc.view.layoutSubtreeIfNeeded()
    return (window, vc)
  }
  private func mouse(
    _ canvas: CanvasView, _ point: CGPoint, _ type: NSEvent.EventType = .leftMouseDown,
    clicks: Int = 1
  ) -> NSEvent {
    NSEvent.mouseEvent(
      with: type, location: canvas.convert(canvas.viewPoint(point), to: nil),
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: canvas.window!.windowNumber, context: nil, eventNumber: 0,
      clickCount: clicks, pressure: 0)!
  }
  private func type(_ value: String, in text: InlineTextView) {
    text.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0))
  }
  func testClickMultilineSelectedColorAndOneStepUndo() throws {
    let (window, vc) = try editor()
    let canvas = vc.canvas
    let session = vc.session
    session.tool = .text
    let p = CGPoint(x: 700, y: 280)
    canvas.mouseDown(with: mouse(canvas, p))
    let text = try XCTUnwrap(canvas.inlineText)
    XCTAssertTrue(window.firstResponder === text)
    XCTAssertNil(window.attachedSheet)
    type("Meet 🐈", in: text)
    text.insertNewline(nil)
    type("there", in: text)
    XCTAssertEqual(text.string, "Meet 🐈\nthere")
    let range = (text.string as NSString).range(of: "there")
    text.setSelectedRange(range)
    text.applyColor(InkColor(rgb: 0xff453a))
    XCTAssertEqual(text.selectedRange(), range)
    XCTAssertEqual(text.annotation.textColors?.first?.range, range)
    XCTAssertEqual(text.annotation.rect.center.distance(to: p), 0, accuracy: 0.01)
    XCTAssertTrue(text.layout.manager.numberOfGlyphs > 0)
    XCTAssertEqual(
      try JSONDecoder().decode(MarkupFile.self, from: JSONEncoder().encode(vc.fileIncludingText))
        .validated(),
      vc.fileIncludingText)
    let expected = try ImageCodec.encode(MarkupRenderer().render(vc.fileIncludingText), type: .png)
    canvas.mouseDown(with: mouse(canvas, CGPoint(x: 55, y: 90)))
    XCTAssertNil(canvas.inlineText)
    XCTAssertEqual(session.selected?.text, text.string)
    XCTAssertEqual(
      try ImageCodec.encode(MarkupRenderer().render(session.file), type: .png), expected)
    session.undo.undo()
    XCTAssertTrue(session.file.annotations.isEmpty)
    session.undo.redo()
    XCTAssertEqual(session.file.annotations.first?.textColors, text.annotation.textColors)
  }
  func testDoubleClickCancelAndDeleteEmptyEmoji() throws {
    let (window, vc) = try editor()
    defer { withExtendedLifetime(window) {} }
    let canvas = vc.canvas
    let session = vc.session
    var a = Annotation(tool: .sticker, rect: CGRect(x: 510, y: 280, width: 160, height: 110))
    a.text = "🦊"
    a.rotation = 0.37
    session.add(a)
    session.tool = .select
    canvas.mouseDown(with: mouse(canvas, a.rect.center, clicks: 2))
    var text = try XCTUnwrap(canvas.inlineText)
    text.selectAll(nil)
    type("🐈", in: text)
    text.cancelOperation(nil)
    XCTAssertEqual(session.file.annotations, [a])
    vc.editSelectedText()
    text = try XCTUnwrap(canvas.inlineText)
    text.selectAll(nil)
    type("😺", in: text)
    vc.finishText()
    XCTAssertEqual(session.selected?.tool, .sticker)
    XCTAssertEqual(session.selected?.rotation, a.rotation)
    XCTAssertEqual(session.selected?.text, "😺")
    vc.editSelectedText()
    text = try XCTUnwrap(canvas.inlineText)
    text.selectAll(nil)
    text.deleteBackward(nil)
    vc.finishText()
    XCTAssertTrue(session.file.annotations.isEmpty)
    session.undo.undo()
    XCTAssertEqual(session.file.annotations.first?.text, "😺")
  }
  func testSaveWithActiveCaptionAndCancelDirtyState() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try SampleImage.file()
    try file.source.write(to: url)
    let doc = try MarkupDocument(opening: url)
    NSDocumentController.shared.addDocument(doc)
    doc.makeWindowControllers()
    defer { doc.close() }
    let vc = try XCTUnwrap(doc.editor)
    vc.editText(at: file.imageBounds.center, annotation: nil)
    var editor = try XCTUnwrap(vc.canvas.inlineText)
    type("Discard", in: editor)
    XCTAssertTrue(doc.isDocumentEdited)
    editor.cancelOperation(nil)
    XCTAssertFalse(doc.isDocumentEdited)
    vc.editText(at: file.imageBounds.center, annotation: nil)
    editor = try XCTUnwrap(vc.canvas.inlineText)
    type("In place", in: editor)
    let expected = try doc.data(ofType: UTType.png.identifier)
    let recovery = try JSONDecoder().decode(MarkupFile.self, from: doc.data(ofType: markupType))
    XCTAssertEqual(recovery.annotations.first?.text, "In place")
    doc.save(nil)
    let timeout = Date(timeIntervalSinceNow: 5)
    while doc.isDocumentEdited, Date() < timeout {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    XCTAssertNil(vc.canvas.inlineText)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertEqual(try Data(contentsOf: url), expected)
    XCTAssertNotEqual(expected, file.source)
  }
  func testInputMethodCompositionAndCommandReturn() throws {
    let (window, vc) = try editor()
    vc.editText(at: CGPoint(x: 555, y: 300), annotation: nil)
    let text = try XCTUnwrap(vc.canvas.inlineText)
    text.setMarkedText(
      "に", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(text.hasMarkedText())
    type("日", in: text)
    XCTAssertFalse(text.hasMarkedText())
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: "\r",
      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    XCTAssertTrue(text.performKeyEquivalent(with: event))
    XCTAssertNil(vc.canvas.inlineText)
    XCTAssertEqual(vc.session.selected?.text, "日")
  }
  func testHoldFillsInkBelowTextAndHoldEraserPreservesEntities() throws {
    let (window, vc) = try editor()
    defer { withExtendedLifetime(window) {} }
    let canvas = vc.canvas
    let session = vc.session
    let p = session.file.imageBounds.center
    var a = Annotation(tool: .text, rect: CGRect(x: 120, y: 85, width: 220, height: 64))
    a.text = "Keep me"
    session.add(a)
    func hold(_ tool: MarkupTool) {
      session.tool = tool
      canvas.mouseDown(with: mouse(canvas, p))
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.82))
      canvas.mouseUp(with: mouse(canvas, p, .leftMouseUp))
    }
    hold(.marker)
    XCTAssertEqual(session.file.paintOrder.map(\.tool), [.fill, .text])
    XCTAssertEqual(session.file.paintOrder.first?.opacity, 0.7)
    hold(.blur)
    XCTAssertTrue(session.file.paintOrder.contains { $0.blursCanvas == true })
    hold(.eraser)
    XCTAssertEqual(session.file.annotations, [a])
    session.undo.undo()
    XCTAssertEqual(session.file.annotations.count, 3)
    let old = session.file
    session.tool = .pen
    canvas.mouseDown(with: mouse(canvas, p))
    canvas.keyDown(
      with: NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.76))
    XCTAssertEqual(session.file, old)
  }
  func testContextMenuTargetsClickedObjectAndSourceSnapHysteresis() throws {
    let (window, vc) = try editor()
    defer { withExtendedLifetime(window) {} }
    let a = Annotation(
      tool: .bubble, rect: CGRect(x: 400, y: 200, width: 300, height: 160), filled: true)
    vc.session.add(a)
    let menu = try XCTUnwrap(vc.canvas.menu(for: mouse(vc.canvas, a.rect.center, .rightMouseDown)))
    XCTAssertEqual(vc.session.selectedID, a.id)
    XCTAssertNotNil(menu.item(withTitle: "Flip"))
    menu.performActionForItem(at: menu.indexOfItem(withTitle: "Duplicate"))
    XCTAssertEqual(vc.session.file.annotations.count, 2)
    let snap = DrawingEntitySnapTool()
    let bounds = CGRect(x: 80, y: 60, width: 500, height: 260)
    var signals: [Bool] = []
    snap.onSnapUpdated = { if $0 == .centerX { signals.append($1) } }
    let p = CGPoint(x: bounds.midX - 3, y: 89)
    let snapped = snap.update(
      bounds: bounds, velocity: .zero, delta: CGPoint(x: 1, y: 0), updatedPosition: p,
      size: a.rect.size)
    XCTAssertEqual(snapped.x, bounds.midX)
    XCTAssertEqual(signals, [true])
    snap.reset()
    XCTAssertEqual(signals.last, false)
  }
  func testCaptionGeometryAndPixelsAgainstTelegramUIKit() throws {
    let base = try ImageCodec.context(width: 400, height: 220)
    let rect = CGRect(x: 0, y: 0, width: 400, height: 220)
    let gray = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.18, alpha: 1).cgColor
    base.setFillColor(gray)
    base.fill(rect)
    let source = try MarkupFile.importing(ImageCodec.encode(base.makeImage()!, type: .png))
    for (style, alignment) in [
      (TextStyle.filled, TextAlignment.center), (.semi, .left), (.stroke, .right),
      (.regular, .center),
    ] {
      var file = source
      var text = Annotation(tool: .text, rect: CGRect(x: 20, y: 20, width: 360, height: 180))
      text.text = "Check this\nlabel"
      text.fontSize = 48
      text.color = InkColor(0.2, 0.65, 0.9)
      text.textStyle = style
      text.alignment = alignment
      file.annotations = [text]
      let textLayout = TelegramTextLayout(text)
      let fit = textLayout.fittedSize(maxWidth: 1080, minimumWidth: 224)
      XCTAssertEqual(fit, CGSize(width: 271, height: 115))
      XCTAssertEqual(textLayout.manager.location(forGlyphAt: 0).y, 45.703125, accuracy: 0.1)
      let url = try XCTUnwrap(
        Bundle(for: Self.self).url(forResource: "ios-" + style.rawValue, withExtension: "png"))
      let reference = try ImageCodec.decode(Data(contentsOf: url))
      let output = try MarkupRenderer().render(file)
      let contexts = try [reference, output].map { image in
        let context = try ImageCodec.context(width: 400, height: 220)
        context.setFillColor(gray)
        context.fill(rect)
        ImageCodec.draw(image, in: rect, context: context)
        return context
      }
      let expected = contexts[0].data!.assumingMemoryBound(to: UInt8.self)
      let actual = contexts[1].data!.assumingMemoryBound(to: UInt8.self)
      var different = 0
      for y in 0..<220 {
        for x in 0..<400 {
          let offset = y * contexts[0].bytesPerRow + 4 * x
          if (0..<3).contains(where: {
            abs(Int(actual[offset + $0]) - Int(expected[offset + $0])) > 16
          }) {
            different += 1
          }
        }
      }
      XCTAssertLessThan(Double(different) / 88000, 0.005, style.rawValue)
      withExtendedLifetime(contexts) {}
    }
  }

  func testEyedropperSamplesCroppedImageAtZoomAndRestoresInput() throws {
    let (window, vc) = try editor()
    let canvas = vc.canvas
    let crop = CGRect(x: 100, y: 100, width: 780, height: 440)
    vc.session.file.crop = crop
    canvas.setZoom(1.6, at: canvas.bounds.center)
    vc.editText(at: crop.center, annotation: nil)
    let text = try XCTUnwrap(canvas.inlineText)
    type("Sample", in: text)
    vc.eyedropper()
    let picker = try XCTUnwrap(canvas.subviews.compactMap { $0 as? EyedropperView }.last)
    let p = CGPoint(x: 150, y: 280)
    picker.update(at: canvas.viewPoint(p))
    XCTAssertEqual(picker.pixel, p - crop.origin)
    XCTAssertEqual(picker.color, InkColor(rgb: 0xffffff))
    picker.finish(true)
    XCTAssertTrue(window.firstResponder === text)
    XCTAssertEqual(text.annotation.text, "Sample")
  }
  func testBrushSettingsMergeAcrossIndependentSessions() throws {
    let domain = "MarkupBrushTest-" + UUID().uuidString
    let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { preferences.removePersistentDomain(forName: domain) }
    let file = try SampleImage.file()
    let a = EditorSession(file: file, preferences: preferences)
    let b = EditorSession(file: file, preferences: preferences)
    a.setBrushSize(0.75)
    b.tool = .marker
    b.color = InkColor(rgb: 0x1c4a55)
    let next = EditorSession(file: file, preferences: preferences)
    XCTAssertEqual(next.drawingState.currentToolState.size, 0.75)
    next.tool = .marker
    XCTAssertEqual(next.color, b.color)
  }

  func testLeftSliderUpdatesSelectedCaptionInOneUndoStep() throws {
    let (window, vc) = try editor()
    var a = Annotation(tool: .text, rect: CGRect(x: 400, y: 200, width: 300, height: 70))
    a.text = "Resize"
    vc.session.add(a)
    vc.session.tool = .select
    vc.session.selectedID = a.id
    let slider = try XCTUnwrap(vc.canvas.subviews.compactMap { $0 as? TelegramSizeSlider }.first)
    func event(_ type: NSEvent.EventType, y: CGFloat) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: slider.convert(CGPoint(x: 15, y: y), to: nil), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    slider.mouseDown(with: event(.leftMouseDown, y: 160))
    slider.mouseDragged(with: event(.leftMouseDragged, y: 100))
    slider.mouseUp(with: event(.leftMouseUp, y: 100))
    let changed = try XCTUnwrap(vc.session.selected)
    XCTAssertGreaterThan(changed.fontSize, a.fontSize)
    XCTAssertEqual(changed.rect.center, a.rect.center)
    vc.session.undo.undo()
    XCTAssertEqual(vc.session.selected, a)
  }
  func testInkTapSelectsShapeWithoutAddingDotAndResumesBrushOnBackgroundClick() throws {
    let (window, vc) = try editor()
    defer { withExtendedLifetime(window) {} }
    let canvas = vc.canvas
    let session = vc.session
    let a = Annotation(
      tool: .rectangle, rect: CGRect(x: 470, y: 250, width: 230, height: 160), filled: true)
    session.add(a)
    session.tool = .pen
    canvas.mouseDown(with: mouse(canvas, a.rect.center))
    canvas.mouseUp(with: mouse(canvas, a.rect.center, .leftMouseUp))
    XCTAssertEqual(session.file.annotations, [a])
    XCTAssertEqual(session.selected?.id, a.id)
    canvas.mouseDown(with: mouse(canvas, CGPoint(x: 65, y: 88)))
    XCTAssertNil(session.selected)
    XCTAssertEqual(session.tool, .pen)
  }
  func testShapeStyleCycleAndBubbleFlipFollowSource() throws {
    let (window, vc) = try editor()
    defer { withExtendedLifetime(window) {} }
    var line = Annotation(tool: .line)
    line.points = [.zero, CGPoint(x: 200, y: 50), CGPoint(x: 400, y: 100)]
    vc.session.add(line)
    vc.session.selectedID = line.id
    for heads in [ArrowHeads.both, .none, .end] {
      vc.cycleObjectStyle()
      XCTAssertEqual(vc.session.selected?.arrowHeads, heads)
    }
    var bubble = Annotation(tool: .bubble, rect: CGRect(x: 160, y: 200, width: 400, height: 300))
    bubble.bubbleTail = CGPoint(x: 0.16, y: 54)
    vc.session.add(bubble)
    vc.session.selectedID = bubble.id
    vc.flipObject()
    XCTAssertEqual(vc.session.selected?.bubbleTail, CGPoint(x: 0.84, y: 54))
    vc.cycleObjectStyle()
    XCTAssertEqual(vc.session.selected?.filled, true)
  }

}
