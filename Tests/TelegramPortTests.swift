import AppKit
import XCTest

@testable import Markup

final class TelegramPortTests: XCTestCase {
  private let size = CGSize(width: 1200, height: 760)
  private func trace(velocity: CGFloat, arrow: Bool = false) -> TelegramPenTool {
    let tool = TelegramPenTool(
      drawingSize: size, color: InkColor(rgb: 0xff453a), lineWidth: 0.23, hasArrow: arrow,
      isEraser: false, isBlur: false, blurredImage: nil, animationsEnabled: false)
    for i in 0...20 {
      let p = DrawingPoint(location: CGPoint(x: 100 + i * 20, y: 200), velocity: velocity)
      tool.updatePath(p, state: i == 0 ? .began : i == 20 ? .ended : .changed, zoomScale: 1)
    }
    return tool
  }
  func testSourceVelocityTapersThePenAndArrowUsesSmoothedTangent() {
    let slow = trace(velocity: 100)
    let fast = trace(velocity: 6000)
    XCTAssertTrue(slow.isValid)
    XCTAssertTrue(fast.isValid)
    XCTAssertGreaterThan(slow.outline.boundingBox.height, fast.outline.boundingBox.height * 2)
    let arrow = trace(velocity: 500, arrow: true)
    XCTAssertTrue(arrow.isValid)
    XCTAssertEqual(arrow.renderLineWidth, 21.168, accuracy: 0.0001)
    XCTAssertEqual(arrow.renderArrowLength, 63.504, accuracy: 0.0001)
    XCTAssertEqual(arrow.arrowStart?.x ?? 0, 500, accuracy: 0.01)
    XCTAssertEqual(abs(arrow.arrowDirection ?? 0), .pi, accuracy: 0.001)
    XCTAssertEqual(
      arrow.arrowLeftPath!.cgPath.currentPoint.x, 500 - 63.504 * cos(0.45), accuracy: 0.001)
    XCTAssertEqual(
      abs(arrow.arrowLeftPath!.cgPath.currentPoint.y - 200), 63.504 * sin(0.45), accuracy: 0.001)
  }
  func testShortArrowIsRejectedLikeUpstream() {
    let tool = TelegramPenTool(
      drawingSize: size, color: InkColor(rgb: 0xff453a), lineWidth: 0.23, hasArrow: true,
      isEraser: false, isBlur: false, blurredImage: nil, animationsEnabled: false)
    let p = DrawingPoint(location: CGPoint(x: 100, y: 200), velocity: 0)
    tool.updatePath(p, state: .began, zoomScale: 1)
    tool.updatePath(p, state: .ended, zoomScale: 1)
    XCTAssertFalse(tool.isValid)
  }
  func testCurveHandlesKeepRelativeBendWhenEndpointsMove() {
    let e = TelegramVectorEntity(
      type: .twoSidedArrow, color: InkColor(rgb: 0xff453a), lineWidth: 0.3)
    e.referenceDrawingSize = size
    e.drawingSize = size
    e.start = CGPoint(x: 100, y: 200)
    e.end = CGPoint(x: 500, y: 200)
    e.mid = (0.5, 0)
    TelegramVectorGeometry.drag(e, handle: 1, delta: CGPoint(x: 0, y: -100))
    XCTAssertEqual(e.mid.0, 0.5, accuracy: 0.001)
    XCTAssertEqual(e.mid.1, -0.25, accuracy: 0.001)
    XCTAssertEqual(TelegramVectorGeometry.midPoint(e), CGPoint(x: 300, y: 100))
    TelegramVectorGeometry.drag(e, handle: 2, delta: CGPoint(x: 400, y: 0))
    XCTAssertEqual(TelegramVectorGeometry.midPoint(e).x, 500, accuracy: 0.001)
    XCTAssertEqual(TelegramVectorGeometry.midPoint(e).y, 0, accuracy: 0.001)
    XCTAssertFalse(TelegramVectorGeometry.path(e).isEmpty)
    TelegramVectorGeometry.drag(e, handle: 0, delta: CGPoint(x: 800, y: 0))
    TelegramVectorGeometry.drag(e, handle: 1, delta: CGPoint(x: 0, y: 20))
    XCTAssertTrue(e.mid.0.isFinite)
    XCTAssertTrue(e.mid.1.isFinite)
  }
  func testDrawingStateDefaultsAndIndependentBrushColors() {
    var state = DrawingState.initial
    XCTAssertEqual(state.selectedTool, .pen)
    XCTAssertEqual(state.currentToolState.color, InkColor(rgb: 0xff453a))
    XCTAssertEqual(state.currentToolState.size, 0.23)
    state = state.withUpdatedColor(InkColor(rgb: 0xffffff)).withUpdatedSelectedTool(.marker)
    XCTAssertEqual(state.currentToolState.color, InkColor(rgb: 0xffd60a))
    XCTAssertEqual(state.currentToolState.size, 0.75)
    state = state.withUpdatedSelectedTool(.pen)
    XCTAssertEqual(state.currentToolState.color, InkColor(rgb: 0xffffff))
  }
  func testPaletteAndBundledGPUAssets() {
    XCTAssertEqual(telegramPaletteColors.count, 120)
    XCTAssertEqual(
      TelegramColorField.gridColor(at: .zero, size: CGSize(width: 360, height: 300)),
      InkColor(rgb: 0xffffff))
    XCTAssertEqual(
      TelegramColorField.gridColor(
        at: CGPoint(x: 359, y: 299), size: CGSize(width: 360, height: 300)), InkColor(rgb: 0xdfeed4)
    )
    XCTAssertEqual(
      TelegramColorField.gridColor(
        at: CGPoint(x: 360, y: 300), size: CGSize(width: 360, height: 300)), InkColor(rgb: 0xdfeed4)
    )
    for name in ["marker", "spectrum", "grayscale", "ToolArrowShadow"] {
      XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "png"))
    }
    XCTAssertNotNil(Bundle.main.url(forResource: "default", withExtension: "metallib"))
  }
  func testColorPickerMouseCoordinatesMatchGridAndSpectrum() throws {
    let picker = TelegramColorPicker(color: InkColor(rgb: 0xff8a00))
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 496), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.contentViewController = picker
    picker.view.layoutSubtreeIfNeeded()
    let root = try XCTUnwrap(picker.view.subviews.first as? NSStackView)
    let field = try XCTUnwrap(
      root.arrangedSubviews.first { $0 is TelegramColorField } as? TelegramColorField)
    var selected: InkColor?
    picker.updated = { selected = $0 }
    func click(_ p: CGPoint) {
      let event = NSEvent.mouseEvent(
        with: .leftMouseDown, location: field.convert(p, to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
      field.mouseDown(with: event)
    }
    click(CGPoint(x: 15, y: 15))
    XCTAssertEqual(selected, InkColor(rgb: 0xffffff))
    field.mode = 1
    click(CGPoint(x: 180, y: 114))
    let green = try XCTUnwrap(selected)
    XCTAssertGreaterThan(green.green, 0.7)
    XCTAssertLessThan(green.red, 0.3)
    XCTAssertLessThan(green.blue, 0.5)
  }
  func testIncrementalMarkerOutputMatchesFreshReplay() throws {
    var file = try SampleImage.file()
    var a = Annotation(tool: .marker)
    a.brushSize = 0.75
    a.inputZoom = 1
    a.color = InkColor(rgb: 0xffd60a)
    let renderer = MarkupRenderer()
    for x in stride(from: 100, through: 500, by: 20) {
      a.points.append(CGPoint(x: x, y: 300))
      a.velocities = (a.velocities ?? []) + [800]
      _ = try renderer.render(file, draft: a)
    }
    file.annotations = [a]
    let incremental = try ImageCodec.encode(renderer.render(file), type: .png)
    let replay = try ImageCodec.encode(MarkupRenderer().render(file), type: .png)
    XCTAssertEqual(incremental, replay)
    XCTAssertNotEqual(replay, file.source)
  }
  func testNativeArrowEventsCommitAndUndo() throws {
    let s = EditorSession(file: try SampleImage.file())
    s.tool = .arrow
    let c = CanvasView(session: s)
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.contentView = c
    c.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    func event(_ type: NSEvent.EventType, _ i: Int) -> NSEvent {
      let p = CGPoint(x: 900 - i * 20, y: 600 - i * 5)
      return NSEvent.mouseEvent(
        with: type, location: c.convert(c.viewPoint(p), to: nil), modifierFlags: [],
        timestamp: Double(i) * 0.02, windowNumber: w.windowNumber, context: nil, eventNumber: i,
        clickCount: 1, pressure: 0)!
    }
    c.mouseDown(with: event(.leftMouseDown, 0))
    for i in 1..<20 {
      c.mouseDragged(with: event(.leftMouseDragged, i))
      _ = try c.renderer.render(s.file, draft: c.draft)
    }
    c.mouseUp(with: event(.leftMouseUp, 20))
    XCTAssertEqual(s.file.annotations.count, 1)
    let saved = try XCTUnwrap(s.file.annotations.first)
    XCTAssertEqual(saved.tool, .arrow)
    XCTAssertEqual(saved.points.last, CGPoint(x: 500, y: 500))
    XCTAssertNotEqual(try ImageCodec.encode(c.renderer.render(s.file), type: .png), s.file.source)
    s.undo.undo()
    XCTAssertTrue(s.file.annotations.isEmpty)
  }
  func testCoalescedTwoPointMouseArrowStillCommitsItsEndpoint() throws {
    let s = EditorSession(file: try SampleImage.file())
    s.tool = .arrow
    let c = CanvasView(session: s)
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.contentView = c
    c.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    func event(_ type: NSEvent.EventType, _ p: CGPoint, _ time: Double) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: c.convert(c.viewPoint(p), to: nil), modifierFlags: [],
        timestamp: time, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 0)!
    }
    c.mouseDown(with: event(.leftMouseDown, CGPoint(x: 900, y: 600), 0))
    c.mouseUp(with: event(.leftMouseUp, CGPoint(x: 500, y: 500), 0.3))
    XCTAssertEqual(s.file.annotations.count, 1)
    XCTAssertEqual(s.file.annotations.first?.points.last, CGPoint(x: 500, y: 500))
  }
  func testSourceTextBubblesFollowMultilineGlyphWidths() throws {
    let manager = TelegramTextLayoutManager()
    let storage = NSTextStorage(
      string: "A much longer line\nShort", attributes: [.font: NSFont.systemFont(ofSize: 28)])
    let container = NSTextContainer(size: CGSize(width: 500, height: 300))
    container.lineFragmentPadding = floor(28 * 0.24)
    storage.addLayoutManager(manager)
    manager.addTextContainer(container)
    manager.frameColor = .red
    manager.ensureLayout(for: container)
    let c = try ImageCodec.context(width: 500, height: 300)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    manager.drawBackground(forGlyphRange: manager.glyphRange(for: container), at: .zero)
    XCTAssertEqual(manager.rectArray.count, 2)
    XCTAssertGreaterThan(manager.rectArray[0].width, manager.rectArray[1].width * 2)
    XCTAssertNotNil(manager.path)
  }
  func testSourceFieldsRoundTripAndValidate() throws {
    var file = try SampleImage.file()
    var a = Annotation(tool: .line)
    a.points = [CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 400)]
    a.vectorMid = CGPoint(x: 0.4, y: -0.2)
    a.vectorWidth = 0.3
    file.annotations = [a]
    let roundTrip = try JSONDecoder().decode(MarkupFile.self, from: JSONEncoder().encode(file))
      .validated()
    XCTAssertEqual(file, roundTrip)
    file.annotations[0].vectorMid = CGPoint(x: CGFloat.infinity, y: 0)
    XCTAssertThrowsError(try file.validated())
  }
}
