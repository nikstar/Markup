import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Markup

final class QuickMarkupTests: XCTestCase {
  func testSaveActionWritesTheOpenedScreenshotAndRetainsLiveUndo() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("Capture.png")
    let source = try SampleImage.file()
    try source.source.write(to: url)
    let doc = try MarkupDocument(opening: url)
    NSDocumentController.shared.addDocument(doc)
    defer { doc.close() }
    XCTAssertEqual(doc.fileURL, url)
    XCTAssertEqual(doc.fileType, UTType.png.identifier)
    var fill = Annotation(tool: .fill)
    fill.color = InkColor(rgb: 0x138d5d)
    doc.session.add(fill)
    let expected = try doc.data(ofType: UTType.png.identifier)
    doc.save(nil)  // Actual responder action behind ⌘S and the Save button.
    let deadline = Date(timeIntervalSinceNow: 5)
    while doc.isDocumentEdited && Date() < deadline {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    XCTAssertFalse(doc.isDocumentEdited)
    let saved = try Data(contentsOf: url)
    XCTAssertEqual(saved, expected)
    XCTAssertEqual(saved.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
    XCTAssertNotEqual(saved, source.source)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["Capture.png"])
    let reopened = try MarkupDocument(opening: url)
    XCTAssertEqual(reopened.session.file.annotations, [fill])
    XCTAssertTrue(reopened.session.undo.canUndo)
    let project = dir.appendingPathComponent("Source.markup")
    try doc.data(ofType: markupType).write(to: project)
    let layered = try MarkupDocument(opening: project)
    XCTAssertEqual(layered.fileType, markupType)
    XCTAssertEqual(layered.session.file.annotations, [fill])
    doc.session.undo.undo()
    XCTAssertEqual(doc.session.file, source)
  }

  func testStillImageFormatAndMultipageImportDestinations() throws {
    let file = try SampleImage.file()
    let doc = MarkupDocument(file: file)
    XCTAssertEqual(doc.fileType, UTType.png.identifier)
    XCTAssertNil(doc.fileURL)
    for type: UTType in [.jpeg, .tiff] {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(type.preferredFilenameExtension!)
      defer { try? FileManager.default.removeItem(at: url) }
      try doc.data(ofType: type.identifier).write(to: url)
      let opened = try MarkupDocument(opening: url)
      XCTAssertEqual(opened.fileType, type.identifier)
      XCTAssertEqual(opened.fileURL, url)
      if type == .tiff {
        let image = try ImageCodec.decode(file.source)
        let dst = try XCTUnwrap(
          CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 2, nil))
        for _ in 0..<2 { CGImageDestinationAddImage(dst, image, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        let multi = try MarkupDocument(opening: url)
        XCTAssertNil(multi.fileURL)
        XCTAssertEqual(multi.fileType, UTType.png.identifier)
      }
    }
  }

  func testOppositeEdgeStaysFixedWithRotationAndMirror() throws {
    var a = Annotation(tool: .rectangle, rect: CGRect(x: 80, y: 65, width: 280, height: 180))
    a.rotation = .pi / 3
    a.flipped = true
    let size = CGSize(width: 800, height: 600)
    let original = TelegramEntitySelection(a, size: size, scale: 1.3)
    XCTAssertEqual(original.handles.count, 8)
    let start = original.handles.last!.point.applying(a.transform)
    XCTAssertEqual(original.hit(start), .edge(1, 1))
    let updated = original.drag(
      .edge(1, 1), from: start, to: start + CGPoint(x: -36, y: 13), constrained: false)
    let result = TelegramEntitySelection(updated, size: size, scale: 1.3)
    let before = original.handles.first!.point.applying(a.transform)
    let after = result.handles.first!.point.applying(updated.transform)
    XCTAssertEqual(before.distance(to: after), 0, accuracy: 0.001)
    let handle = result.handles.last!.point.applying(updated.transform)
    XCTAssertEqual(handle.distance(to: start + CGPoint(x: -36, y: 13)), 0, accuracy: 0.001)
  }

  func testZoomPinsPointerWithCropAndPanAndUsesPhysicalPixels() throws {
    let s = EditorSession(file: try SampleImage.file())
    s.file.crop = CGRect(x: 220, y: 130, width: 750, height: 400)
    let c = CanvasView(session: s)
    let w = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 580, height: 380), styleMask: .borderless,
      backing: .buffered, defer: false)
    w.contentView = c
    c.pan = CGPoint(x: 48, y: -17)
    let pointer = CGPoint(x: 455, y: 125)
    let original = c.imagePoint(pointer)
    c.setZoom(3.2, at: pointer)
    XCTAssertEqual(c.imagePoint(pointer).distance(to: original), 0, accuracy: 0.001)
    c.actualSize()
    XCTAssertEqual(c.pixelScale, 1, accuracy: 0.0001)
    c.fit()
    XCTAssertEqual(c.pan, .zero)
    XCTAssertEqual(c.viewport.center, c.bounds.center)
  }
}
