import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import Markup

@MainActor
final class PreviewWindowTests: XCTestCase {
  func testWelcomeOpenButtonAndDropKeepFileIdentity() throws {
    var opened = 0
    var files = [URL]()
    var images = [Data]()
    let window = MarkupWindow.welcome(open: { opened += 1 }, files: { files.append($0) },
                                      image: { data, _ in images.append(data) })
    defer { window.close() }
    XCTAssertEqual(window.frame.size, CGSize(width: 372, height: 224))
    XCTAssertFalse(window.isOpaque)
    XCTAssertTrue(window.titlebarAppearsTransparent)
    let drop = try XCTUnwrap(window.contentView as? WelcomeDropView)
    let material = try XCTUnwrap(drop.subviews.compactMap { $0 as? NSGlassEffectView }.first)
    XCTAssertEqual(material.style, .regular)
    window.contentView?.layoutSubtreeIfNeeded()
    let open = drop.openButton
    let frame = try XCTUnwrap(drop.superview)
    let hit = frame.hitTest(open.convert(open.bounds.center, to: frame))
    XCTAssertTrue(hit === open || hit?.isDescendant(of: open) == true)
    open.performClick(nil)
    XCTAssertEqual(opened, 1)

    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let png = try SampleImage.file().source
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    try png.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    board.writeObjects([file as NSURL])
    XCTAssertTrue(drop.openDrop(board))
    XCTAssertEqual(files, [file])
    XCTAssertTrue(images.isEmpty)
    board.clearContents()
    board.setData(png, forType: .png)
    XCTAssertTrue(drop.openDrop(board))
    XCTAssertEqual(images, [png])
    board.clearContents()
    board.setString("plain text", forType: .string)
    XCTAssertFalse(drop.openDrop(board))
  }

  func testOpeningSizeUsesImageResolutionAndAvailableScreenHeight() {
    let retina = CGSize(width: 2056, height: 1290)
    func fit(_ w: CGFloat, _ h: CGFloat, screen: CGSize, scale: CGFloat = 2) -> CGSize {
      MarkupWindow.editorSize(image: CGSize(width: w, height: h), available: screen,
                              backingScale: scale, titleHeight: 40)
    }
    XCTAssertEqual(fit(986, 1912, screen: retina), CGSize(width: 509, height: 1148))
    let laptop = CGSize(width: 1280, height: 800)
    let tall = fit(1206, 2622, screen: laptop)
    XCTAssertEqual(tall.height, laptop.height - 24)
    XCTAssertEqual(tall.width, MarkupWindow.minimumEditorSize.width)
    let pano = fit(3200, 1200, screen: laptop, scale: 1)
    XCTAssertEqual(pano.width, laptop.width - 24)
    XCTAssertLessThan(pano.height, laptop.height - 24)
    XCTAssertEqual(fit(80, 160, screen: retina), MarkupWindow.minimumEditorSize)
  }

  func testNewPortraitDocumentOpensAtFitAfterWideDocument() throws {
    var file = try SampleImage.file()
    let wide = MarkupDocument(file: file)
    wide.makeWindowControllers()
    let lastWindow = try XCTUnwrap(wide.windowControllers.first?.window)
    defer { wide.close() }
    lastWindow.setFrame(CGRect(x: 0, y: 0, width: 1080, height: 500), display: false)
    // The visible image can also be a portrait crop of a landscape source.
    file.crop = CGRect(x: 20, y: 0, width: 300, height: 760)
    let portrait = MarkupDocument(file: file)
    portrait.makeWindowControllers()
    defer { portrait.close() }
    let editor = try XCTUnwrap(portrait.editor)
    let window = try XCTUnwrap(editor.view.window)
    editor.view.layoutSubtreeIfNeeded()
    XCTAssertLessThan(window.frame.width, EditorToolShelf.singleRowWidth)
    XCTAssertEqual(window.frameAutosaveName, "")
    XCTAssertTrue(editor.canvas.editingBounds.contains(editor.canvas.viewport))
    XCTAssertEqual(editor.canvas.pixelScale, 1, accuracy: 0.001)
    XCTAssertEqual(editor.canvas.viewport.height * window.backingScaleFactor, 760, accuracy: 0.001)

    let properties = try XCTUnwrap(window.toolbar?.items.compactMap { $0.view as? NSButton }
      .first { $0.accessibilityIdentifier() == "Properties" })
    properties.performClick(nil)
    editor.view.layoutSubtreeIfNeeded()
    XCTAssertEqual(editor.canvas.bounds.width, editor.view.bounds.width)
    window.setFrame(CGRect(x: 0, y: 0, width: 900, height: 640), display: false)
    editor.view.layoutSubtreeIfNeeded()
    XCTAssertLessThan(editor.canvas.bounds.width, editor.view.bounds.width)
  }

  func testCanvasAndShelfFitSmallestDocumentWindowInBothAppearances() throws {
    let session = EditorSession(file: try SampleImage.file())
    let vc = EditorViewController(session: session)
    let window = MarkupWindow.editor(vc, title: "Screenshot")
    defer { window.close() }
    window.setFrame(CGRect(origin: .zero, size: MarkupWindow.minimumEditorSize), display: false)
    XCTAssertFalse(window.isOpaque)
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertNil(vc.view.appearance)
    XCTAssertNil(vc.canvas.layer?.backgroundColor)
    let original = try vc.canvas.renderer.render(session.file)
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
      window.appearance = NSAppearance(named: appearance)
      for tool in [MarkupTool.pen, .text, .rectangle] {
        session.tool = tool
        vc.view.layoutSubtreeIfNeeded()
        func visibleViews(_ v: NSView) -> [NSView] {
          v.isHidden ? [] : [v] + v.subviews.flatMap(visibleViews)
        }
        let views = visibleViews(vc.view)
        let swatches = views.compactMap { $0 as? SwatchButton }
        XCTAssertEqual(swatches.count, 9)
        let occupied = vc.view.convert(vc.canvas.editingBounds, from: vc.canvas)
        let shelfControls: [NSView] = swatches + views.compactMap { $0 as? NSButton }.filter { ["mode_draw", "mode_text"].contains($0.accessibilityIdentifier()) }
        for control in shelfControls {
          let rect = vc.view.convert(control.bounds, from: control)
          XCTAssertTrue(vc.view.bounds.contains(rect))
          XCTAssertFalse(occupied.intersects(rect))
        }
        XCTAssertGreaterThanOrEqual(vc.canvas.editingBounds.height, 240)
        XCTAssertTrue(vc.canvas.editingBounds.contains(vc.canvas.viewport))
      }
    }
    let output = try vc.canvas.renderer.render(session.file)
    XCTAssertEqual(try ImageCodec.encode(output, type: .png), try ImageCodec.encode(original, type: .png))
  }

  func testShelfAnchorsSurviveModeSwitchesAndKeepFitBesideCrop() throws {
    let session = EditorSession(file: try SampleImage.file())
    let vc = EditorViewController(session: session)
    let window = MarkupWindow.editor(vc, title: "Shelf")
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(vc.view)
    let brushes = try XCTUnwrap(views.compactMap { $0 as? TelegramToolsPanel }.first)
    func button(_ id: String) throws -> NSButton {
      try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == id })
    }
    let draw = try button("mode_draw"), text = try button("mode_text")
    let shapes = try button("addObject"), spectrum = try button("colorPicker")
    let crop = try button("tool_crop"), fit = try button("fitCanvas"), stickers = try button("addSticker")
    func rect(_ view: NSView) -> CGRect { view.convert(view.bounds, to: vc.view) }
    let swatches = views.compactMap { $0 as? SwatchButton }.filter { !$0.isHiddenOrHasHiddenAncestor }
    for width in [MarkupWindow.minimumEditorSize.width, 715, 716, 748, 1080, 509] {
      window.setFrame(CGRect(x: 0, y: 0, width: width, height: 500), display: false)
      vc.view.layoutSubtreeIfNeeded()
      let frame = rect(brushes)
      let cells = brushes.subviews.map(rect)
      let fixedViews = swatches + [spectrum, draw, text, shapes, stickers, crop, fit]
      let saved = fixedViews.map(rect)
      XCTAssertEqual(frame.midX, vc.view.bounds.midX, accuracy: 0.01)
      XCTAssertEqual(frame.minY, vc.view.bounds.minY, accuracy: 0.01)
      XCTAssertEqual(cells.count, 6)
      XCTAssertEqual(swatches.count, 9)
      XCTAssertEqual(Set(swatches.map { rect($0).midY }).count, 2)
      XCTAssertEqual(Set(swatches.map { rect($0).midX }).count, 5)
      let black = try XCTUnwrap(swatches.first { $0.accessibilityLabel() == "Black" })
      XCTAssertEqual(rect(black).midX, rect(spectrum).midX, accuracy: 0.01)
      XCTAssertLessThan(rect(black).midY, rect(spectrum).midY)
      black.performClick(nil)
      XCTAssertEqual(session.color, InkColor(rgb: 0))
      XCTAssertTrue(black.chosen)
      XCTAssertEqual(swatches.filter(\.chosen).count, 1)
      XCTAssertTrue(saved.allSatisfy(vc.view.bounds.contains))
      if width < EditorToolShelf.singleRowWidth {
        XCTAssertTrue(saved.allSatisfy { $0.minY >= frame.maxY }, "width \(width), brushes \(frame), controls \(saved)")
        XCTAssertLessThan(swatches.map { rect($0).maxX }.max()!, rect(draw).minX)
      } else {
        let palette = try XCTUnwrap(spectrum.superview as? NSGridView)
        let gap = rect(draw).minX - frame.maxX
        XCTAssertEqual(frame.minX - rect(palette).maxX, gap, accuracy: 0.01)
        XCTAssertEqual(gap, min(32, (width - frame.width) / 2 - 206 - 12), accuracy: 0.01)
      }
      XCTAssertGreaterThan(rect(draw).midY, rect(text).midY)
      XCTAssertEqual(rect(draw).midX, rect(text).midX)
      XCTAssertLessThan(rect(shapes).maxX, rect(stickers).minX)
      XCTAssertLessThan(rect(stickers).maxX, rect(crop).minX)
      XCTAssertTrue(vc.view.bounds.contains(rect(fit)))
      XCTAssertTrue(fit.isHidden)
      XCTAssertLessThan(rect(crop).maxX, rect(fit).minX)
      XCTAssertEqual(fit.imagePosition, .imageOnly)
      XCTAssertNotNil(fit.image)
      XCTAssertTrue(brushes.subviews[1].accessibilityPerformPress())
      XCTAssertEqual(session.tool, .arrow)
      text.performClick(nil)
      vc.editText(at: vc.canvas.insertionCenter, annotation: nil)
      vc.view.layoutSubtreeIfNeeded()
      XCTAssertTrue(brushes.isHidden)
      XCTAssertEqual(text.state, .on)
      XCTAssertEqual(fixedViews.map(rect), saved)
      let format = try XCTUnwrap(views.compactMap { $0 as? TelegramTextSettings }.first)
      XCTAssertTrue(frame.contains(rect(format)))
      draw.performClick(nil)
      vc.view.layoutSubtreeIfNeeded()
      XCTAssertFalse(brushes.isHidden)
      XCTAssertEqual(session.tool, .arrow)
      XCTAssertEqual(brushes.subviews.map(rect), cells)
      XCTAssertEqual(fixedViews.map(rect), saved)
      vc.canvas.pan = CGPoint(x: 10, y: -10)
      XCTAssertTrue(fit.isHidden)
      for zoom: CGFloat in [2, 0.8] {
        vc.canvas.setZoom(zoom, at: vc.canvas.editingBounds.center)
        vc.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(fit.isHidden)
        XCTAssertEqual(fit.alphaValue, 1)
        XCTAssertEqual(fixedViews.map(rect), saved)
        fit.performClick(nil)
        vc.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(vc.canvas.zoom, 1)
        XCTAssertEqual(vc.canvas.pan, .zero)
        XCTAssertTrue(fit.isHidden)
        XCTAssertEqual(fixedViews.map(rect), saved)
      }
    }
  }

  func testBrushMagnificationKeepsHitTargetsAndSizeDragStable() throws {
    let session = EditorSession(file: try SampleImage.file())
    let vc = EditorViewController(session: session)
    let window = MarkupWindow.editor(vc, title: "Brushes")
    defer { window.close() }
    vc.view.layoutSubtreeIfNeeded()
    func panel(in view: NSView) -> TelegramToolsPanel? {
      (view as? TelegramToolsPanel) ?? view.subviews.lazy.compactMap { panel(in: $0) }.first
    }
    let tools = try XCTUnwrap(panel(in: vc.view))
    let slots = tools.subviews
    XCTAssertEqual(slots.map(\.toolTip), ["Pen (P)", "Arrow (A)", "Marker (M)", "Neon (N)", "Blur (B)", "Eraser (E)"])
    let original = slots.map(\.frame)
    let marker = slots[2]
    let art = try XCTUnwrap(marker.layer?.sublayers?.first)
    let neighbor = try XCTUnwrap(slots[3].layer?.sublayers?.first)
    let idle = art.transform.m11, resting = art.position
    func event(_ type: NSEvent.EventType, offset: CGFloat = 0) -> NSEvent {
      let p = marker.convert(CGPoint(x: marker.bounds.midX, y: marker.bounds.midY + offset), to: nil)
      return NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    tools.mouseMoved(with: event(.mouseMoved))
    XCTAssertGreaterThan(art.transform.m11, neighbor.transform.m11)
    XCTAssertGreaterThan(neighbor.transform.m11, idle)
    XCTAssertLessThan(art.position.y, resting.y)
    let hovered = art.transform.m11
    let target = try XCTUnwrap(tools.hitTest(tools.convert(marker.frame.center, to: tools.superview)))
    XCTAssertTrue(target === marker)
    target.mouseDown(with: event(.leftMouseDown))
    target.mouseUp(with: event(.leftMouseUp))
    XCTAssertEqual(session.tool, .marker)
    XCTAssertGreaterThan(art.transform.m11, hovered)
    let size = try XCTUnwrap(session.drawingState.currentToolState.size)
    target.mouseDown(with: event(.leftMouseDown))
    target.mouseDragged(with: event(.leftMouseDragged, offset: -16))
    target.mouseUp(with: event(.leftMouseUp, offset: -16))
    XCTAssertEqual(try XCTUnwrap(session.drawingState.currentToolState.size), min(size + 0.16, 1), accuracy: 0.001)
    XCTAssertNil(vc.canvas.brushPreview)
    tools.mouseExited(with: NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
    XCTAssertGreaterThan(art.transform.m11, idle)
    XCTAssertEqual(neighbor.transform.m11, idle)
    XCTAssertEqual(slots.map(\.frame), original)
  }

  func testZoomUnderBothToolbarsKeepsPointerAndControlsIndependent() throws {
    for embedded in [false, true] {
      let session = EditorSession(file: try SampleImage.file())
      let vc = EditorViewController(session: session)
      vc.isExtension = embedded
      let window: NSWindow
      if embedded {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 540),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = vc
      } else {
        window = MarkupWindow.editor(vc, title: "Zoom")
      }
      defer { window.close() }
      vc.view.layoutSubtreeIfNeeded()
      let canvas = vc.canvas
      let area = canvas.editingBounds
      XCTAssertGreaterThan(area.minY, canvas.bounds.minY)
      XCTAssertLessThan(area.maxY, canvas.bounds.maxY)
      let original = try ImageCodec.encode(canvas.renderer.render(session.file), type: .png)
      let fitted = canvas.viewport
      XCTAssertTrue(area.contains(fitted))
      func blurBands() -> [CALayer] {
        (canvas.layer?.sublayers ?? []).filter { ["Title bar blur", "Tool shelf blur"].contains($0.name ?? "") }
      }
      // At first contact the blur covers just the image's three-point overlap.
      // In particular, a narrow image leaves both clear glass side margins alone.
      canvas.setZoom((area.height + 6) / fitted.height, at: area.center)
      canvas.needsLayout = true
      canvas.layoutSubtreeIfNeeded()
      XCTAssertEqual(blurBands().count, 2)
      for band in blurBands() {
        XCTAssertEqual(band.frame.height, 3, accuracy: 0.01)
        XCTAssertEqual(band.frame.width, canvas.bounds.intersection(canvas.viewport).width, accuracy: 0.01)
      }
      canvas.fit()
      let anchor = area.center + CGPoint(x: 27, y: -12)
      let source = canvas.imagePoint(anchor)
      canvas.setZoom(3, at: anchor)
      XCTAssertLessThan(canvas.imagePoint(anchor).distance(to: source), 0.0001)
      XCTAssertLessThan(canvas.viewport.minY, canvas.bounds.minY)
      XCTAssertGreaterThan(canvas.viewport.maxY, canvas.bounds.maxY)
      for y in [area.minY - 5, area.maxY + 5] {
        let p = canvas.convert(CGPoint(x: area.midX, y: y), to: canvas.superview)
        XCTAssertNil(canvas.hitTest(p))
      }
      XCTAssertTrue(canvas.hitTest(canvas.convert(anchor, to: canvas.superview)) === canvas)
      canvas.needsLayout = true
      canvas.layoutSubtreeIfNeeded()
      XCTAssertEqual(blurBands().count, 2)
      XCTAssertTrue(blurBands().allSatisfy { !$0.frame.intersects(area) })
      XCTAssertNil(canvas.layer?.filters?.first)
      XCTAssertEqual(try ImageCodec.encode(canvas.renderer.render(session.file), type: .png), original)
      canvas.fit()
      canvas.needsLayout = true
      canvas.layoutSubtreeIfNeeded()
      XCTAssertNil(canvas.layer?.filters?.first)
      XCTAssertTrue(blurBands().isEmpty)
      XCTAssertNil(canvas.layer?.mask)
      XCTAssertEqual(canvas.viewport, fitted)
      XCTAssertTrue(session.file.annotations.isEmpty)
    }
  }
}
