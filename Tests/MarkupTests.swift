import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Markup

final class MarkupTests: XCTestCase {
  func image(width: Int = 200, height: Int = 120, color: NSColor = .white) throws -> MarkupFile {
    let c = try ImageCodec.context(width: width, height: height)
    c.setFillColor(color.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try MarkupFile.importing(ImageCodec.encode(c.makeImage()!, type: .png))
  }
  func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    // Redraw into an explicit RGBA context so tests don't depend on ImageIO's byte order.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(
      data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * 4, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = c.data!.assumingMemoryBound(to: UInt8.self)
    let i = (y * image.width + x) * 4
    return Array(UnsafeBufferPointer(start: bytes + i, count: 4))
  }
  func transact(_ session: EditorSession, _ body: () -> Void) {
    session.undo.beginUndoGrouping()
    body()
    session.undo.endUndoGrouping()
  }
  func testImageKeepsPixelDimensionsAndOrientation() throws {
    let file = try image(width: 97, height: 61)
    XCTAssertEqual(file.width, 97)
    XCTAssertEqual(file.height, 61)
    let rendered = try MarkupRenderer().render(file)
    XCTAssertEqual(rendered.width, 97)
    XCTAssertEqual(rendered.height, 61)
  }
  func testEXIFOrientationIsNormalized() throws {
    let base = try ImageCodec.decode(image(width: 80, height: 40).source)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
      data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, base, [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let file = try MarkupFile.importing(data as Data)
    XCTAssertEqual(file.width, 40)
    XCTAssertEqual(file.height, 80)
  }
  func testSourceAndExportAreNotVerticallyMirrored() throws {
    let c = try ImageCodec.context(width: 50, height: 100)
    c.setFillColor(NSColor.red.cgColor)
    c.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
    c.setFillColor(NSColor.blue.cgColor)
    c.fill(CGRect(x: 0, y: 50, width: 50, height: 50))
    let f = try MarkupFile.importing(ImageCodec.encode(c.makeImage()!, type: .png))
    let out = try MarkupRenderer().render(f)
    XCTAssertGreaterThan(pixel(out, 25, 10)[0], 240)
    XCTAssertGreaterThan(pixel(out, 25, 90)[2], 240)
  }
  func testEraserRevealsOriginalInsteadOfErasingScreenshot() throws {
    var file = try image()
    var pen = Annotation(tool: .pen)
    pen.points = stride(from: 20, through: 180, by: 10).map { CGPoint(x: $0, y: 60) }
    pen.lineWidth = 20
    pen.color = InkColor(1, 0, 0)
    file.annotations.append(pen)
    var eraser = Annotation(tool: .eraser)
    eraser.points = stride(from: 20, through: 100, by: 10).map { CGPoint(x: 100, y: $0) }
    eraser.lineWidth = 30
    file.annotations.append(eraser)
    let out = try MarkupRenderer().render(file)
    XCTAssertEqual(pixel(out, 100, 60), [255, 255, 255, 255])
    XCTAssertGreaterThan(pixel(out, 40, 60)[0], 240)
    XCTAssertLessThan(pixel(out, 40, 60)[1], 20)
    XCTAssertEqual(file.source, try image().source)
  }
  func testCropUsesSourcePixelsAndKeepsAllObjects() throws {
    var file = try image()
    file.crop = CGRect(x: 30, y: 20, width: 75, height: 45)
    let out = try MarkupRenderer().render(file)
    XCTAssertEqual(out.width, 75)
    XCTAssertEqual(out.height, 45)
    XCTAssertEqual(file.width, 200)
    XCTAssertEqual(file.height, 120)
  }
  func testRedactionIsOpaqueEvenWithLowOpacity() throws {
    var file = try image()
    var redaction = Annotation(tool: .redact)
    redaction.rect = CGRect(x: 40, y: 30, width: 80, height: 50)
    redaction.opacity = 0.1
    file.annotations = [redaction]
    XCTAssertEqual(pixel(try MarkupRenderer().render(file), 60, 50), [0, 0, 0, 255])
  }
  func testMarkerIsTranslucent() throws {
    var file = try image()
    var a = Annotation(tool: .marker)
    a.color = InkColor(1, 0, 0)
    a.points = stride(from: 20, through: 180, by: 10).map { CGPoint(x: $0, y: 60) }
    file.annotations = [a]
    let p = pixel(try MarkupRenderer().render(file), 100, 60)
    XCTAssertGreaterThan(p[1], 0)
    XCTAssertLessThan(p[1], 240)
    XCTAssertEqual(p[3], 255)
  }
  func testUndoRedoAndBranchingHistory() throws {
    let s = EditorSession(file: try image())
    transact(s) {
      s.add(Annotation(tool: .rectangle, rect: CGRect(x: 10, y: 10, width: 20, height: 20)))
    }
    XCTAssertEqual(s.file.annotations.count, 1)
    s.undo.undo()
    XCTAssertEqual(s.file.annotations.count, 0)
    s.undo.redo()
    XCTAssertEqual(s.file.annotations.count, 1)
    s.undo.undo()
    transact(s) {
      s.add(Annotation(tool: .ellipse, rect: CGRect(x: 10, y: 10, width: 20, height: 20)))
    }
    XCTAssertFalse(s.undo.canRedo)
    XCTAssertEqual(s.file.annotations[0].tool, .ellipse)
  }
  func testSelectionTransformUndoRestoresPoints() throws {
    let s = EditorSession(file: try image())
    var a = Annotation(tool: .arrow)
    a.points = [CGPoint(x: 1, y: 2), CGPoint(x: 30, y: 40)]
    transact(s) { s.add(a) }
    s.selectedID = a.id
    transact(s) { s.updateSelected(name: "Move") { $0.translate(CGPoint(x: 20, y: 10)) } }
    XCTAssertEqual(s.selected?.points.first, CGPoint(x: 21, y: 12))
    s.undo.undo()
    XCTAssertEqual(s.file.annotations[0].points, a.points)
  }
  func testDuplicateGetsNewIdentityAndCanBeDeleted() throws {
    let s = EditorSession(file: try image())
    let a = Annotation(tool: .rectangle, rect: CGRect(x: 10, y: 10, width: 30, height: 20))
    transact(s) { s.add(a) }
    s.selectedID = a.id
    transact(s) { s.duplicateSelected() }
    XCTAssertEqual(s.file.annotations.count, 2)
    XCTAssertNotEqual(s.selectedID, a.id)
    transact(s) { s.deleteSelected() }
    XCTAssertEqual(s.file.annotations, [a])
  }
  func testProjectRoundTripPreservesEditableFeatures() throws {
    var file = try image()
    for (i, tool) in MarkupTool.allCases.enumerated() {
      var a = Annotation(tool: tool, rect: CGRect(x: 10, y: 10, width: 50, height: 30))
      a.text = "Text 😀\nLine 2"
      a.rotation = CGFloat(i) / 10
      a.textStyle = .stroke
      file.annotations.append(a)
    }
    file.crop = CGRect(x: 5, y: 5, width: 180, height: 100)
    let decoded = try JSONDecoder().decode(MarkupFile.self, from: JSONEncoder().encode(file))
      .validated()
    XCTAssertEqual(decoded, file)
  }
  func testEveryToolRendersWithoutLosingAlphaOrDimensions() throws {
    for tool in MarkupTool.allCases {
      var file = try image()
      var a = Annotation(tool: tool, rect: CGRect(x: 40, y: 20, width: 100, height: 60))
      a.points =
        tool.isBrush || tool == .line
        ? [CGPoint(x: 30, y: 30), CGPoint(x: 80, y: 80), CGPoint(x: 160, y: 40)] : []
      a.text = "Hello"
      a.fontSize = 20
      file.annotations = [a]
      let out = try MarkupRenderer().render(file)
      XCTAssertEqual(out.width, 200, "\(tool)")
      XCTAssertEqual(pixel(out, 0, 0)[3], 255, "\(tool)")
    }
  }
  func testAllTextStylesRenderVisibleText() throws {
    let renderer = MarkupRenderer()
    let base = try image(color: .lightGray)
    let original = try ImageCodec.encode(renderer.render(base), type: .png)
    for style in TextStyle.allCases {
      var file = base
      var a = Annotation(tool: .text, rect: CGRect(x: 10, y: 10, width: 180, height: 80))
      a.text = "Hello"
      a.fontSize = 32
      a.textStyle = style
      file.annotations = [a]
      XCTAssertNotEqual(try ImageCodec.encode(renderer.render(file), type: .png), original)
    }
  }
  func testBlurAndPixelationChangePatternOnlyInsideStroke() throws {
    let c = try ImageCodec.context(width: 200, height: 120)
    for x in 0..<200 {
      c.setFillColor((x % 2 == 0 ? NSColor.white : NSColor.black).cgColor)
      c.fill(CGRect(x: x, y: 0, width: 1, height: 120))
    }
    let base = try MarkupFile.importing(ImageCodec.encode(c.makeImage()!, type: .png))
    for tool in [MarkupTool.blur, .pixelate] {
      var file = base
      var a = Annotation(tool: tool)
      a.points = stride(from: 20, through: 180, by: 10).map { CGPoint(x: $0, y: 60) }
      a.lineWidth = 20
      file.annotations = [a]
      let out = try MarkupRenderer().render(file)
      XCTAssertEqual(pixel(out, 50, 5), pixel(try ImageCodec.decode(base.source), 50, 5))
      XCTAssertNotEqual(pixel(out, 50, 60), pixel(try ImageCodec.decode(base.source), 50, 60))
    }
  }
  func testRotatedHitTestingUsesActualPath() throws {
    var a = Annotation(tool: .rectangle, rect: CGRect(x: 40, y: 20, width: 80, height: 50))
    a.rotation = .pi / 4
    a.filled = true
    XCTAssertTrue(MarkupRenderer.hit(a, point: a.rect.center, tolerance: 2))
    XCTAssertFalse(MarkupRenderer.hit(a, point: CGPoint(x: 0, y: 0), tolerance: 2))
  }
  func testCropAndAnnotationOrientationAgree() throws {
    var f = try image()
    var a = Annotation(tool: .redact)
    a.rect = CGRect(x: 20, y: 10, width: 40, height: 20)
    f.annotations = [a]
    f.crop = a.rect
    XCTAssertEqual(pixel(try MarkupRenderer().render(f), 10, 10), [0, 0, 0, 255])
  }
  func testUnsupportedAndMalformedDocumentsFail() throws {
    XCTAssertThrowsError(try MarkupFile.importing(Data("invalid".utf8)))
    var f = try image()
    f.version = 2
    XCTAssertThrowsError(try f.validated())
    f.version = 1
    f.width = 16385
    XCTAssertThrowsError(try f.validated())
    f = try image()
    f.crop = CGRect(x: 400, y: 400, width: 10, height: 10)
    XCTAssertThrowsError(try f.validated())
    f = try image()
    var a = Annotation(tool: .pen)
    a.lineWidth = -.infinity
    f.annotations = [a]
    XCTAssertThrowsError(try f.validated())
  }
  func testPNGJPEGAndPDFExport() throws {
    let file = try image(width: 180, height: 90)
    let r = MarkupRenderer()
    for type in [UTType.png, .jpeg, .tiff] {
      let result = try ImageCodec.decode(ImageCodec.encode(r.render(file), type: type))
      XCTAssertEqual(result.width, 180)
      XCTAssertEqual(result.height, 90)
    }
    let pdf = try r.pdf(file)
    XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
  }
  func testTelegramCurveAndShapePathsAreFinite() {
    let curve = CGPath.curve(
      start: CGPoint(x: 0, y: 50), end: CGPoint(x: 180, y: 50), mid: CGPoint(x: 90, y: 10),
      lineWidth: 6, arrowSize: CGSize(width: 10, height: 20), twoSided: true)
    XCTAssertGreaterThan(curve.boundingBox.width, 100)
    XCTAssertFalse(curve.isEmpty)
    XCTAssertFalse(
      CGPath.star(in: CGRect(x: 0, y: 0, width: 80, height: 80), extrusion: 18).isEmpty)
  }
  func testNeonHasAWhiteCoreAndColoredGlow() throws {
    var file = try image(width: 800, height: 500, color: .black)
    var a = Annotation(tool: .neon)
    a.color = InkColor(rgb: 0xbf5af2)
    a.brushSize = 0.4
    a.points = stride(from: 100, through: 700, by: 20).map { CGPoint(x: $0, y: 250) }
    file.annotations = [a]
    let rendered = try MarkupRenderer().render(file)
    XCTAssertGreaterThan(pixel(rendered, 400, 250)[0], 240)
    XCTAssertGreaterThan(pixel(rendered, 400, 275)[2], 20)
    XCTAssertEqual(pixel(rendered, 400, 400), [0, 0, 0, 255])
  }
  func testNativeDocumentSaveAndRead() throws {
    let file = try image()
    let doc = MarkupDocument(file: file)
    let data = try doc.data(ofType: markupType)
    try doc.read(from: data, ofType: markupType)
    XCTAssertEqual(doc.session.file, file)
  }
  func testActionExtensionDataRoundTrip() throws {
    let original = try image(width: 123, height: 67)
    let provider = ExtensionTransport.provider(png: original.source)
    XCTAssertTrue(ExtensionTransport.canRead(provider))
    let done = expectation(description: "Extension image transfer")
    ExtensionTransport.load(provider) { result in
      switch result {
      case .success(let f):
        XCTAssertEqual(f.width, 123)
        XCTAssertEqual(f.height, 67)
      case .failure(let error): XCTFail(error.localizedDescription)
      }
      done.fulfill()
    }
    wait(for: [done], timeout: 5)
  }
  func testDocumentDirtyStateReturnsToCleanAfterUndo() throws {
    let directory = try DropDirectory()
    let doc = MarkupDocument(file: try image())
    doc.newImageDirectory = directory.url
    defer { doc.close(); withExtendedLifetime(directory) {} }
    XCTAssertFalse(doc.isDocumentEdited)
    doc.session.add(Annotation(tool: .rectangle, rect: CGRect(x: 1, y: 1, width: 30, height: 30)))
    XCTAssertTrue(doc.isDocumentEdited)
    doc.session.undo.undo()
    XCTAssertFalse(doc.isDocumentEdited)
  }

  func testEachBrushRemembersItsSettings() throws {
    let s = EditorSession(file: try image())
    s.width = 12
    s.color = InkColor(0, 1, 0)
    s.tool = .marker
    s.width = 18
    s.color = InkColor(1, 0, 0)
    s.tool = .pen
    XCTAssertEqual(s.width, 12)
    XCTAssertEqual(s.color, InkColor(0, 1, 0))
    s.tool = .marker
    XCTAssertEqual(s.width, 18)
    XCTAssertEqual(s.color, InkColor(1, 0, 0))
  }
  func testEmptyShapeDraftsRenderSafely() throws {
    for tool in [MarkupTool.bubble, .star, .ellipse, .rectangle] {
      let file = try image()
      let out = try MarkupRenderer().render(file, draft: Annotation(tool: tool))
      XCTAssertEqual(out.width, 200)
    }
  }
  func testCanvasMouseDrawingSelectionAndUndo() throws {
    let s = EditorSession(file: try image(width: 1000, height: 600))
    let c = CanvasView(session: s)
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.contentView = c
    c.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: c.convert(c.viewPoint(p), to: nil), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    c.mouseDown(with: event(.leftMouseDown, CGPoint(x: 200, y: 200)))
    c.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 500, y: 200)))
    c.mouseUp(with: event(.leftMouseUp, CGPoint(x: 500, y: 200)))
    XCTAssertEqual(s.file.annotations.count, 1)
    XCTAssertEqual(s.file.annotations[0].tool, .pen)
    s.tool = .select
    c.mouseDown(with: event(.leftMouseDown, CGPoint(x: 300, y: 200)))
    c.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 350, y: 250)))
    c.mouseUp(with: event(.leftMouseUp, CGPoint(x: 350, y: 250)))
    XCTAssertNotNil(s.selectedID)
    XCTAssertEqual(s.file.annotations[0].points[0].x, 250, accuracy: 0.01)
    s.undo.undo()
    XCTAssertEqual(s.file.annotations[0].points[0].x, 200, accuracy: 0.01)
    s.undo.undo()
    XCTAssertTrue(s.file.annotations.isEmpty)
  }
  func testCanvasCropAndEscapeCancel() throws {
    let s = EditorSession(file: try image(width: 1000, height: 600))
    s.tool = .crop
    let c = CanvasView(session: s)
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.contentView = c
    c.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: c.convert(c.viewPoint(p), to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    c.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 100)))
    c.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 600, y: 400)))
    c.mouseUp(with: event(.leftMouseUp, CGPoint(x: 600, y: 400)))
    XCTAssertEqual(s.file.visibleRect.size.width, 500, accuracy: 1)
    XCTAssertEqual(s.file.visibleRect.size.height, 300, accuracy: 1)
    s.undo.undo()
    XCTAssertNil(s.file.crop)
    s.tool = .pen
    c.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 100)))
    c.keyDown(
      with: NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: w.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
    c.mouseUp(with: event(.leftMouseUp, CGPoint(x: 100, y: 100)))
    XCTAssertTrue(s.file.annotations.isEmpty)
  }

  func testOriginalTelegramToolArtworkIsBundled() {
    for name in ["ToolPen", "ToolArrow", "ToolMarker", "ToolNeon", "ToolBlur", "ToolEraser"] {
      XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "png"), name)
    }
  }

  func testPrimaryIconIsCompiledIntoTheAssetCatalog() {
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "Markup")
    XCTAssertNotNil(Bundle.main.url(forResource: "Assets", withExtension: "car"))
  }

}
