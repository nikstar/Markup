import AppKit
import XCTest

@testable import Markup

final class StrokeLifecycleTests: XCTestCase {
  func testHighFrequencyMouseInputMatchesTelegramDrawingCadence() {
    // Same motion from a 62.5 Hz device and a 1,000 Hz device whose positions
    // arrive in 4 ms bursts. Raw adjacent-event velocity used to alternate
    // between zero and four times the intended speed, changing stroke width.
    func samples(step: Int, bursts: Bool) -> [DrawingPoint] {
      var input = TelegramStrokeInput()
      var result = [input.begin(at: .zero, time: 0)]
      for ms in stride(from: step, through: 320, by: step) {
        let x = CGFloat(bursts ? (ms / 4) * 4 : ms)
        if let point = input.sample(at: CGPoint(x: x, y: x / 2), time: Double(ms) / 1000) {
          result.append(point)
        }
      }
      result.append(input.sample(at: CGPoint(x: 325, y: 162.5), time: 0.325, ending: true)!)
      return result
    }
    let reference = samples(step: 16, bursts: false)
    let bursty = samples(step: 1, bursts: true)
    XCTAssertEqual(reference.count, 22)
    XCTAssertEqual(reference.map(\.location), bursty.map(\.location))
    for (a, b) in zip(reference, bursty) {
      XCTAssertEqual(a.velocity, b.velocity, accuracy: 0.0001)
    }
    XCTAssertEqual(bursty.last?.location, CGPoint(x: 325, y: 162.5))
  }

  private func pen(arrow: Bool) -> TelegramPenTool {
    TelegramPenTool(
      drawingSize: CGSize(width: 1200, height: 760), color: InkColor(rgb: 0xff8a00),
      lineWidth: 0.23, hasArrow: arrow, isEraser: false, isBlur: false,
      blurredImage: nil, animationsEnabled: true)
  }
  private func feed(_ pen: TelegramPenTool, ending: Bool = true) {
    for i in 0...20 {
      pen.updatePath(
        DrawingPoint(location: CGPoint(x: 100 + i * 20, y: 250 + i * 3), velocity: 1000),
        state: i == 0 ? .began : i == 20 && ending ? .ended : .changed, zoomScale: 1)
    }
  }
  func testArrowheadRevealsFromTipWithSourceTimingAndRoundedCaps() throws {
    let pen = pen(arrow: true)
    let preview = pen.setupRenderView()
    let window = NSWindow(
      contentRect: CGRect(x: 40, y: 40, width: 600, height: 380),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Arrow animation regression test"
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 380))
    window.contentView = host
    host.addSubview(preview)
    let drawingBounds = preview.bounds
    preview.frame = host.bounds
    preview.bounds = drawingBounds
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    feed(pen)
    preview.displayIfNeeded()
    CATransaction.flush()
    let done = expectation(description: "arrow reveal completed")
    preview.animateArrowPaths(
      start: try XCTUnwrap(pen.arrowStart), direction: try XCTUnwrap(pen.arrowDirection),
      length: pen.renderArrowLength, lineWidth: pen.renderArrowLineWidth
    ) { done.fulfill() }
    let wings = preview.layer!.sublayers!.compactMap { $0 as? CAShapeLayer }.filter {
      $0.animation(forKey: "arrowReveal") != nil
    }
    XCTAssertEqual(wings.count, 2)
    for wing in wings {
      let animation = try XCTUnwrap(wing.animation(forKey: "arrowReveal") as? CABasicAnimation)
      XCTAssertEqual(animation.keyPath, "strokeEnd")
      XCTAssertEqual(animation.fromValue as? Double, 0)
      XCTAssertEqual(animation.toValue as? Double, 1)
      XCTAssertEqual(animation.duration, 0.2)
      XCTAssertEqual(animation.timingFunction, CAMediaTimingFunction(name: .easeInEaseOut))
      XCTAssertEqual(wing.lineCap, .round)
      XCTAssertEqual(wing.lineWidth, pen.renderArrowLineWidth * 0.33, accuracy: 0.001)
      XCTAssertEqual(
        wing.path?.boundingBoxOfPath.maxX ?? 0, pen.arrowStart!.x * 0.33, accuracy: 0.001)
    }
    CATransaction.flush()
    let halfway = expectation(description: "wings are partially revealed on screen")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
      for wing in wings {
        let progress = (wing.presentation() as? CAShapeLayer)?.strokeEnd ?? -1
        XCTAssertGreaterThan(progress, 0.01)
        XCTAssertLessThan(progress, 0.99)
      }
      halfway.fulfill()
    }
    wait(for: [halfway, done], timeout: 2)
    // Wings stay visible while the last drying layers complete, then the
    // canvas swaps to the full committed bitmap. No disappear/reappear flash.
    XCTAssertTrue(wings.allSatisfy { $0.superlayer != nil && $0.strokeEnd == 1 })
    preview.cancel()
  }
  func testPenAndArrowKeepSourceDryingTransition() throws {
    for arrow in [false, true] {
      let pen = pen(arrow: arrow)
      let preview = pen.setupRenderView()
      feed(pen)
      let drying = preview.layer!.sublayers!.compactMap { $0 as? CAShapeLayer }.filter {
        $0.animation(forKey: "inkDrying") != nil
      }
      XCTAssertFalse(drying.isEmpty)
      XCTAssertTrue(preview.isDryingUp)
      for layer in drying {
        let animation = try XCTUnwrap(layer.animation(forKey: "inkDrying") as? CABasicAnimation)
        XCTAssertEqual(animation.duration, 0.4)
        XCTAssertEqual(animation.fromValue as? CGFloat, pen.renderLineWidth * 0.4)
        XCTAssertEqual(animation.toValue as? Double, 0)
        XCTAssertEqual(animation.timingFunction, CAMediaTimingFunction(name: .linear))
      }
      preview.cancel()
    }
  }
  func testReleaseDelayAndDryingHandOffCompleteWithoutAnotherEvent() throws {
    let pen = pen(arrow: true)
    let preview = pen.setupRenderView()
    let window = NSWindow(
      contentRect: CGRect(x: 40, y: 40, width: 600, height: 380),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Arrow release regression test"
    let host = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 380))
    window.contentView = host
    host.addSubview(preview)
    let drawingBounds = preview.bounds
    preview.frame = host.bounds
    preview.bounds = drawingBounds
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    feed(pen)
    preview.displayIfNeeded()
    CATransaction.flush()
    let settled = expectation(description: "finished preview hands off without pointer movement")
    preview.settled = { settled.fulfill() }
    preview.finish()
    XCTAssertTrue(preview.isFinishingArrow)
    XCTAssertFalse(
      preview.layer!.sublayers!.contains { $0.animation(forKey: "arrowReveal") != nil })
    let revealing = expectation(description: "release delay starts the reveal")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
      XCTAssertEqual(
        preview.layer!.sublayers!.filter { $0.animation(forKey: "arrowReveal") != nil }.count, 2)
      revealing.fulfill()
    }
    wait(for: [revealing, settled], timeout: 2)
    XCTAssertTrue(preview.arrowFinished)
    XCTAssertFalse(preview.isDryingUp)
    XCTAssertFalse(preview.isFinishingArrow)
    preview.cancel()
  }
  func testNativeReleaseCommitsOnceAndUndoCancelsPreview() throws {
    let s = EditorSession(file: try SampleImage.file())
    s.tool = .arrow
    let c = CanvasView(session: s)
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.contentView = c
    s.onChange = { [weak c] in c?.invalidate() }
    func event(_ type: NSEvent.EventType, _ i: Int) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: c.convert(c.viewPoint(CGPoint(x: 100 + i * 20, y: 250)), to: nil),
        modifierFlags: [], timestamp: Double(i) * 0.02, windowNumber: w.windowNumber,
        context: nil, eventNumber: i, clickCount: 1, pressure: 0)!
    }
    c.mouseDown(with: event(.leftMouseDown, 0))
    for i in 1..<20 { c.mouseDragged(with: event(.leftMouseDragged, i)) }
    c.mouseUp(with: event(.leftMouseUp, 20))
    XCTAssertEqual(s.file.annotations.count, 1)
    let a = try XCTUnwrap(s.file.annotations.first)
    XCTAssertEqual(a.hasTerminalSample, true)
    XCTAssertEqual(c.penPreviews.count, 1)
    XCTAssertTrue(try XCTUnwrap(c.penPreviews[a.id]).isFinishingArrow)
    // Save/reopen while the wings are animating has the complete final arrow.
    let reopened = try JSONDecoder().decode(MarkupFile.self, from: JSONEncoder().encode(s.file))
    XCTAssertEqual(
      try ImageCodec.encode(c.renderer.render(s.file), type: .png),
      try ImageCodec.encode(MarkupRenderer().render(reopened), type: .png))
    s.undo.undo()
    XCTAssertTrue(c.penPreviews.isEmpty)
    let noDelayedCommit = expectation(description: "no deferred document mutation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { noDelayedCommit.fulfill() }
    wait(for: [noDelayedCommit], timeout: 2)
    XCTAssertTrue(s.file.annotations.isEmpty)
    s.undo.redo()
    XCTAssertEqual(s.file.annotations.count, 1)
  }
  func testTerminalSampleReplayMatchesDirectSourceForAllBrushes() throws {
    let size = CGSize(width: 1200, height: 760)
    for tool: MarkupTool in [.pen, .arrow, .marker, .neon, .eraser, .blur] {
      var a = Annotation(tool: tool)
      a.brushSize = 0.23
      a.inputZoom = 1
      a.hasTerminalSample = true
      a.points = (0...20).map { CGPoint(x: 100 + $0 * 20, y: 250 + $0 * 2) }
      a.velocities = (0...20).map { CGFloat(500 + $0 * 20) }
      let incremental = TelegramStrokeRenderer()
      var draft = a
      draft.hasTerminalSample = nil
      for n in 1..<a.points.count {
        draft.points = Array(a.points.prefix(n))
        draft.velocities = Array(a.velocities!.prefix(n))
        let c = try ImageCodec.context(width: 1200, height: 760)
        try incremental.draw(draft, size: size, live: true, context: c)
      }
      let c = try ImageCodec.context(width: 1200, height: 760)
      let r = try ImageCodec.context(width: 1200, height: 760)
      try incremental.draw(a, size: size, live: false, context: c)
      try TelegramStrokeRenderer().draw(a, size: size, live: false, context: r)
      XCTAssertEqual(
        try ImageCodec.encode(c.makeImage()!, type: .png),
        try ImageCodec.encode(r.makeImage()!, type: .png), tool.rawValue)
      if tool == .arrow || tool == .pen {
        let source = TelegramPenTool(
          drawingSize: size, color: a.color, lineWidth: 0.23,
          hasArrow: tool == .arrow, isEraser: false, isBlur: false,
          blurredImage: nil, animationsEnabled: false)
        for i in a.points.indices {
          source.updatePath(
            DrawingPoint(location: a.points[i], velocity: a.velocities![i]),
            state: i == 0 ? .began : i == a.points.count - 1 ? .ended : .changed, zoomScale: 1)
        }
        let direct = try ImageCodec.context(width: 1200, height: 760)
        source.draw(in: direct, size: size)
        XCTAssertEqual(
          try ImageCodec.encode(c.makeImage()!, type: .png),
          try ImageCodec.encode(direct.makeImage()!, type: .png))
      }
    }
  }
}
