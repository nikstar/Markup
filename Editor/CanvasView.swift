import AppKit

final class CanvasView: NSView {
  let session: EditorSession
  let renderer = MarkupRenderer()
  let editingGuide = NSLayoutGuide()
  var editingBounds: CGRect { editingGuide.frame.isEmpty ? bounds : editingGuide.frame }
  private let toolbarBlur = CanvasToolbarBlur()
  private var lastEditingBounds = CGRect.null
  var onText: ((CGPoint, Annotation?) -> Void)?
  private(set) var inlineText: InlineTextView?
  private var textSurface = TextEditingSurface()
  private var outgoingText: Annotation?
  fileprivate var hiddenTextID: UUID? { inlineText?.annotation.id ?? outgoingText?.id }
  func presentText(_ text: InlineTextView) {
    stopSelectionPulse()
    outgoingText = nil
    inlineText = text
    textSurface.removeFromSuperview()
    textSurface = TextEditingSurface()
    addSubview(textSurface, positioned: .below, relativeTo: subviews.first { $0 is TelegramSizeSlider })
    textSurface.position(in: self)
    textSurface.attach(text, in: self)
    textSurface.reveal()
    textSurface.animatePose(of: text, entering: true)
    setAccessibilityRole(.group)
    invalidate()
    window?.makeFirstResponder(text)
  }
  func refreshTextBackdrop() { textSurface.refreshBackdrop() }
  func dismissText(returning caption: Annotation?) {
    inlineText?.removeFromSuperview()
    inlineText = nil
    outgoingText = caption
    let surface = textSurface
    let resting = caption.map { a -> InlineTextView in
      let text = InlineTextView(annotation: a, existing: true, imageBounds: session.file.visibleRect, zoom: zoom)
      text.isEditable = false
      text.isSelectable = false
      surface.attach(text, in: self)
      return text
    }
    surface.dismiss(text: resting) { [weak self, weak surface] in
      guard let self, self.textSurface === surface else { return }
      self.outgoingText = nil
      self.invalidate()
    }
    setAccessibilityRole(.image)
    invalidate()
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard editingBounds.contains(convert(point, from: superview)) else { return nil }
    return super.hitTest(point)
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    toolbarBlur.updateColors(in: effectiveAppearance)
  }
  override func resetCursorRects() {
    super.resetCursorRects()
    if session.tool == .text { addCursorRect(viewport.intersection(editingBounds), cursor: .iBeam) }
  }
  var onSticker: ((CGPoint) -> Void)?
  var onDrop: ((URL, CGPoint) -> Void)?
  var onEntityMenu: ((Annotation) -> NSMenu)?
  var onDrawingChanged: (() -> Void)?
  var onToolChange: (() -> Void)?
  var onError: ((Error) -> Void)?
  var onZoomChanged: ((CGFloat) -> Void)?
  private(set) var zoom: CGFloat = 1 {
    didSet {
      needsDisplay = true
      if zoom != oldValue { onZoomChanged?(zoom) }
    }
  }
  var backingScale: CGFloat { window?.backingScaleFactor ?? 1 }
  var pixelScale: CGFloat { scale * backingScale }
  var pan = CGPoint.zero
  private(set) var draft: Annotation? { didSet { if (oldValue == nil) != (draft == nil) { onDrawingChanged?() } } }
  private var cachedRegion = CGRect.null
  private var cachedResolution: CGFloat = 0
  private var cached: CGImage?
  private var start = CGPoint.zero
  private var lastView = CGPoint.zero
  private var resumeBrush: MarkupTool?
  private var tapCandidate: Annotation?
  private var lastDragTime: TimeInterval = 0
  private var lastRotation: CGFloat = 0
  private let snapTool = DrawingEntitySnapTool()
  private var guideLayers: [DrawingEntitySnapTool.SnapType: CAShapeLayer] = [:]
  private var original: MarkupFile?
  private var originalAnnotation: Annotation?
  private var dragHandle: SelectionHandle?
  private var panning = false
  private var spaceDown = false
  private var hold: DispatchWorkItem?
  private var cropDraft: CGRect?
  private var strokeInput = TelegramStrokeInput()
  private let previewClip = StrokePreviewClip()
  private let entitiesAboveInk = EntityPreviewOverlay()
  fileprivate var selectionStart: CFTimeInterval?
  private var selectionTimer: Timer?
  private var fillHold: DispatchWorkItem?
  private var fillCircle: CAShapeLayer?
  private(set) var penPreviews: [UUID: TelegramPenTool.RenderView] = [:]
  var brushPreview: CGFloat? { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var undoManager: UndoManager? { session.undo }
  init(session: EditorSession) {
    self.session = session
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = true
    previewClip.wantsLayer = true
    previewClip.layer?.masksToBounds = true
    addSubview(previewClip)
    addSubview(entitiesAboveInk)
    entitiesAboveInk.canvas = self
    snapTool.onSnapUpdated = { [weak self] type, visible in self?.showGuide(type, visible: visible) }
    registerForDraggedTypes([.fileURL, .png, .tiff])
    setAccessibilityElement(true)
    setAccessibilityIdentifier("markupCanvas")
    setAccessibilityLabel("Markup canvas")
    setAccessibilityRole(.image)
  }
  required init?(coder: NSCoder) { fatalError() }
  static let fitPadding = CGSize(width: 16, height: 12)
  static func fitScale(image: CGSize, area: CGSize, backingScale: CGFloat) -> CGFloat {
    min(1 / backingScale, max(1, area.width - fitPadding.width) / image.width,
        max(1, area.height - fitPadding.height) / image.height)
  }
  var viewport: CGRect {
    let area = editingBounds
    let size = session.file.visibleRect.size
    let fit = Self.fitScale(image: size, area: area.size, backingScale: backingScale)
    let target = CGSize(width: size.width * fit * zoom, height: size.height * fit * zoom)
    return CGRect(
      x: area.midX - target.width / 2 + pan.x, y: area.midY - target.height / 2 + pan.y,
      width: target.width, height: target.height)
  }
  var scale: CGFloat { viewport.width / session.file.visibleRect.width }
  var insertionCenter: CGPoint {
    let visible = editingBounds.intersection(viewport)
    return visible.isEmpty ? session.file.visibleRect.center : imagePoint(visible.center)
  }
  func imagePoint(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: (point.x - viewport.minX) / scale + session.file.visibleRect.minX,
      y: (point.y - viewport.minY) / scale + session.file.visibleRect.minY)
  }
  func viewPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: (point.x - session.file.visibleRect.minX) * scale + viewport.minX,
      y: (point.y - session.file.visibleRect.minY) * scale + viewport.minY)
  }
  func invalidate() {
    if let outgoingText, session.file.annotations.first(where: { $0.id == outgoingText.id }) != outgoingText {
      self.outgoingText = nil
      textSurface.removeFromSuperview()
    }
    let visibleIDs = Set(session.file.annotations.map(\.id) + (draft.map { [$0.id] } ?? []))
    for id in Array(penPreviews.keys) where !visibleIDs.contains(id) { removePreview(id) }
    entitiesAboveInk.needsDisplay = true
    cached = nil
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
    setAccessibilityValue(
      "\(session.file.annotations.count) annotations, \(session.tool.title) tool")
  }
  private func removePreview(_ id: UUID) {
    penPreviews.removeValue(forKey: id)?.cancel()
    cached = nil
    needsDisplay = true
  }
  private func layoutPreviews() {
    if let layer {
      toolbarBlur.update(layer: layer, editing: editingBounds, image: viewport, scale: backingScale)
    }
    if textSurface.superview != nil { textSurface.position(in: self) }
    entitiesAboveInk.frame = bounds
    entitiesAboveInk.isHidden = (penPreviews.isEmpty && fillCircle == nil && selectionStart == nil) || session.file.separatesInk != true
    let crop = session.file.visibleRect
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewClip.frame = viewport
    for preview in penPreviews.values {
      let drawingBounds = preview.bounds
      preview.frame = CGRect(
        x: -crop.minX * scale, y: -crop.minY * scale,
        width: session.file.size.width * scale, height: session.file.size.height * scale)
      preview.bounds = drawingBounds
    }
    CATransaction.commit()
  }
  override func layout() {
    super.layout()
    if lastEditingBounds != editingBounds {
      lastEditingBounds = editingBounds
      window?.invalidateCursorRects(for: self)
      needsDisplay = true
    }
    layoutPreviews()
  }
  private func beginPreview(_ a: Annotation) {
    do {
      guard let preview = try renderer.makePenPreview(a, size: session.file.size) else { return }
      penPreviews[a.id] = preview
      previewClip.addSubview(preview)
      preview.settled = { [weak self] in self?.removePreview(a.id) }
      layoutPreviews()
      cached = nil
    } catch { onError?(error) }
  }
  func fit() {
    zoom = 1
    pan = .zero
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    layoutPreviews()
    guard let c = NSGraphicsContext.current?.cgContext else { return }
    let v = viewport
    c.saveGState()
    // Only the image has a checkerboard. The surrounding canvas shows the window material.
    c.clip(to: v)
    let visible = v.intersection(bounds)
    if !visible.isNull {
      for y in stride(
        from: v.minY + floor((visible.minY - v.minY) / 16) * 16, to: visible.maxY, by: 16)
      {
        for x in stride(
          from: v.minX + floor((visible.minX - v.minX) / 16) * 16, to: visible.maxX, by: 16)
        {
          c.setFillColor(
            NSColor(
              calibratedWhite: (Int((x - v.minX) / 16) + Int((y - v.minY) / 16)) % 2 == 0
                ? 0.9 : 0.8,
              alpha: 1
            ).cgColor)
          c.fill(CGRect(x: x, y: y, width: 16, height: 16))
        }
      }
    }
    if !visible.isEmpty {
      // Render the visible image pixels at display resolution. Magnification
      // can reveal full-size detail without allocating a full zoomed bitmap.
      let region = CGRect(
        origin: imagePoint(visible.origin),
        size: CGSize(width: visible.width / scale, height: visible.height / scale)
      )
      .integral.intersection(session.file.visibleRect)
      let resolution = ceil(max(region.width, region.height) * min(1, pixelScale))
      do {
        let image: CGImage
        if let draft, penPreviews[draft.id] == nil {
          image = try renderer.render(
            session.file, maxDimension: resolution, draft: draft,
            hiddenStrokeIDs: entitiesAboveInk.isHidden ? [] : Set(session.file.annotations.filter { !$0.tool.isInk }.map(\.id)), region: region)
        } else {
          if cached == nil || cachedRegion != region || cachedResolution != resolution {
            var hidden = Set(penPreviews.keys)
            if let hiddenTextID { hidden.insert(hiddenTextID) }
            if !entitiesAboveInk.isHidden {
              hidden.formUnion(session.file.annotations.filter { !$0.tool.isInk }.map(\.id))
            }
            cached = try renderer.render(
              session.file, maxDimension: resolution, draft: draft,
              hiddenStrokeIDs: hidden, region: region)
            cachedRegion = region
            cachedResolution = resolution
          }
          image = cached!
        }
        let destination = CGRect(
          origin: viewPoint(region.origin),
          size: CGSize(width: region.width * scale, height: region.height * scale))
        ImageCodec.draw(image, in: destination, context: c)
      } catch { /* Import and export surface rendering errors in the controller. */  }
    }
    c.restoreGState()
    if let a = session.selected, draft == nil, inlineText == nil, selectionStart == nil { drawSelection(a, c: c) }
    if let value = brushPreview {
      let diameter =
        TelegramBrushMetrics.width(session.tool, size: session.file.size, value: value / zoom)
        * scale
      c.setFillColor(session.color.ns.withAlphaComponent(0.7).cgColor)
      c.fillEllipse(
        in: CGRect(
          x: editingBounds.midX - diameter / 2, y: editingBounds.midY - diameter / 2, width: diameter,
          height: diameter))
    }
    if let crop = cropDraft {
      let r = CGRect(
        origin: viewPoint(crop.origin),
        size: CGSize(width: crop.width * scale, height: crop.height * scale))
      c.setStrokeColor(NSColor.white.cgColor)
      c.setLineWidth(1.5)
      c.setLineDash(phase: 0, lengths: [6, 4])
      c.stroke(r)
    }
  }
  // DrawingEntityView.animateSelection: the entity compresses and returns while
  // its handles fade and expand after a 100 ms delay. Keep paint order intact.
  private func pulseSelection(_ a: Annotation) {
    stopSelectionPulse()
    guard !a.tool.isInk, session.file.separatesInk == true,
          !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    selectionStart = CACurrentMediaTime()
    let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] timer in
      guard let self, let start = self.selectionStart, self.session.selectedID == a.id,
            CACurrentMediaTime() - start < 0.33 else {
        timer.invalidate()
        self?.stopSelectionPulse()
        return
      }
      self.entitiesAboveInk.needsDisplay = true
    }
    selectionTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    invalidate()
  }
  private func stopSelectionPulse() {
    guard selectionStart != nil else { return }
    selectionTimer?.invalidate()
    selectionTimer = nil
    selectionStart = nil
    invalidate()
  }
  private func drawSelection(_ a: Annotation, c: CGContext) {
    c.saveGState()
    let origin = viewPoint(.zero)
    c.translateBy(x: origin.x, y: origin.y)
    c.scaleBy(x: scale, y: scale)
    selection(a).draw(in: c, backingScale: backingScale)
    c.restoreGState()
  }
  private func selection(_ a: Annotation) -> TelegramEntitySelection {
    TelegramEntitySelection(a, size: session.file.size, scale: scale)
  }
  private func showGuide(_ type: DrawingEntitySnapTool.SnapType, visible: Bool) {
    var key = type
    var angle: CGFloat?
    if case .rotation(let value) = type { key = .rotation(nil); angle = value }
    guard visible || guideLayers[key] != nil else { return }
    let guide = guideLayers[key] ?? CAShapeLayer()
    if guide.superlayer == nil { layer?.addSublayer(guide); guideLayers[key] = guide }
    let oldOpacity = guide.presentation()?.opacity ?? (visible ? 0 : 1)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if visible {
      let v = viewport
      let path = CGMutablePath()
      let start: CGPoint, end: CGPoint
      switch type {
      case .top, .centerY, .bottom:
        let y = type == .top ? v.minY : type == .bottom ? v.maxY : v.midY
        start = CGPoint(x: v.minX, y: y); end = CGPoint(x: v.maxX, y: y)
      case .left, .centerX, .right:
        let x = type == .left ? v.minX : type == .right ? v.maxX : v.midX
        start = CGPoint(x: x, y: v.minY); end = CGPoint(x: x, y: v.maxY)
      case .rotation:
        start = viewPoint(session.selected?.rect.center ?? insertionCenter)
        end = start.pointAt(distance: max(v.width, v.height), angle: angle ?? 0)
      }
      path.move(to: start); path.addLine(to: end)
      guide.frame = bounds
      guide.path = path
      guide.lineWidth = 1 + 1 / backingScale
      guide.lineDashPattern = angle == nil ? nil : [12, 12]
      guide.strokeColor = NSColor(rgb: angle == nil ? 0x5fc1f0 : 0xffd70a).cgColor
    }
    let opacity: Float = visible ? 1 : 0
    if guide.opacity != opacity || guide.animation(forKey: "opacity") == nil && visible {
      guide.opacity = opacity
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = oldOpacity; fade.toValue = opacity
      fade.duration = visible ? 0.2 : 0.4
      fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      guide.add(fade, forKey: "opacity")
    }
    CATransaction.commit()
  }

  private func entity(at point: CGPoint) -> Annotation? {
    session.file.paintOrder.reversed().first {
      $0.tool != .eraser && MarkupRenderer.hit($0, point: point, tolerance: 8 / scale, size: session.file.size)
    }
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    if let inlineText { inlineText.onFinish?(true) }
    let point = imagePoint(convert(event.locationInWindow, from: nil))
    guard session.file.visibleRect.contains(point), let a = entity(at: point) else { return nil }
    session.tool = .select
    session.selectedID = a.id
    return onEntityMenu?(a)
  }
  override func mouseDown(with event: NSEvent) {
    if let inlineText { inlineText.onFinish?(true); return }
    if outgoingText != nil { outgoingText = nil; textSurface.removeFromSuperview(); invalidate() }
    // Telegram does not start a new gesture while its arrowhead is revealing.
    guard !penPreviews.values.contains(where: { $0.isFinishingArrow }) else { return }
    // Other operations must see the complete committed drawing, including ink
    // whose transient drying layer is still visible.
    if session.tool != .pen && session.tool != .arrow {
      for id in Array(penPreviews.keys) { removePreview(id) }
    }
    window?.makeFirstResponder(self)
    let v = convert(event.locationInWindow, from: nil)
    let p = imagePoint(v)
    start = p
    lastDragTime = event.timestamp
    lastView = v
    panning = spaceDown || event.buttonNumber == 2
    tapCandidate = nil
    if panning { return }
    guard viewport.contains(v) || session.selected != nil else { return }
    if session.tool == .select {
      original = session.file
      dragHandle = session.selected.flatMap { selection($0).hit(p) }
      if dragHandle == nil {
        let selected = session.selected
        let preciseHit = entity(at: p)
        // A selected outline can also be moved by grabbing its empty interior.
        let insideSelection =
          selected.map { $0.rawBounds.contains(p.applying($0.transform.inverted())) } ?? false
        session.selectedID = preciseHit?.id ?? (insideSelection ? selected?.id : nil)
        if event.clickCount == 1, let hit = session.selected, selected?.id != hit.id { pulseSelection(hit) }
      }
      originalAnnotation = session.selected
      if session.selected == nil, let resumeBrush {
        self.resumeBrush = nil
        session.tool = resumeBrush
        original = nil
        return
      }
      if let a = originalAnnotation {
        snapTool.maybeSkipFromStart(bounds: session.file.visibleRect, position: a.bounds.center)
        snapTool.maybeSkipFromStart(rotation: a.rotation)
        lastRotation = a.rotation
      }
      if event.clickCount == 2, let a = session.selected,
        a.tool == .text || (a.tool == .sticker && a.imageData == nil)
      {
        original = nil
        originalAnnotation = nil
        onText?(p, a)
      }
      return
    }
    guard session.file.visibleRect.contains(p) else { return }
    session.selectedID = nil
    if session.tool == .text {
      let existing = session.file.annotations.reversed().first { $0.tool == .text && MarkupRenderer.hit($0, point: p, tolerance: 0, size: session.file.size) }
      onText?(p, existing)
      return
    }
    if session.tool == .sticker {
      onSticker?(p)
      return
    }
    if session.tool == .fill {
      var a = session.makeAnnotation(at: .zero)
      a.rect = session.file.imageBounds
      session.add(a)
      return
    }
    if session.tool == .crop {
      cropDraft = CGRect(origin: p, size: .zero)
      return
    }
    var a = session.makeAnnotation(at: p)
    if a.tool.telegramKey != nil {
      tapCandidate = session.file.paintOrder.reversed().first {
        !$0.tool.isInk && MarkupRenderer.hit($0, point: p, tolerance: 1 / scale, size: session.file.size)
      }
    }
    if a.tool.isBrush {
      a.points = [p]
      a.pressures = [pressure(event)]
    }
    if a.tool == .line {
      a.points = [p, p, p]
      a.vectorMid = CGPoint(x: 0.5, y: 0)
      a.vectorWidth = 0.3
    }
    if a.tool.telegramKey != nil {
      a.brushSize = (a.brushSize ?? 0.5) / zoom
      a.inputZoom = zoom
      a.velocities = [0]
      a.lineWidth = TelegramBrushMetrics.width(a.tool, size: session.file.size, value: a.brushSize!)
    }
    _ = strokeInput.begin(at: p, time: event.timestamp)
    draft = a
    beginPreview(a)
    if a.tool.telegramKey != nil { armFill(for: a, at: p) }
    needsDisplay = true
  }

  // DrawingView.handleLongPress starts feedback at 450 ms and commits 250 ms later.
  private func armFill(for stroke: Annotation, at point: CGPoint) {
    cancelFill()
    let start = DispatchWorkItem { [weak self] in
      guard let self, self.draft?.id == stroke.id, self.session.tool == stroke.tool else { return }
      var fill = Annotation(tool: .fill, rect: self.session.file.imageBounds, color: stroke.color)
      fill.opacity = stroke.opacity * (stroke.tool == .marker ? 0.7 : 1)
      if stroke.tool == .blur { fill.blursCanvas = true }
      if ![.eraser, .blur].contains(stroke.tool) {
        let circle = CAShapeLayer()
        let diameter = 160 * self.scale
        circle.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        circle.path = CGPath(ellipseIn: circle.bounds, transform: nil)
        circle.position = self.viewPoint(point) - self.viewport.origin
        circle.fillColor = fill.color.ns.withAlphaComponent(fill.color.alpha * fill.opacity).cgColor
        self.previewClip.layer?.addSublayer(circle)
        self.fillCircle = circle
        self.invalidate()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.01; grow.toValue = 12; grow.duration = 0.35
        grow.fillMode = .forwards; grow.isRemovedOnCompletion = false
        grow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        circle.add(grow, forKey: "grow")
      }
      let finish = DispatchWorkItem { [weak self] in
        guard let self, self.draft?.id == stroke.id, self.session.tool == stroke.tool else { return }
        self.draft = nil
        self.removePreview(stroke.id)
        self.cancelFill()
        if [.blur, .eraser].contains(stroke.tool) {
          let transition = CATransition()
          transition.type = .fade; transition.duration = 0.2
          self.layer?.add(transition, forKey: "fill")
        }
        if stroke.tool == .eraser {
          var next = self.session.file
          next.annotations.removeAll { $0.tool.isInk }
          self.session.commit(next, name: "Erase Drawing")
        } else { self.session.add(fill) }
        self.invalidate()
      }
      self.fillHold = finish
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: finish)
    }
    fillHold = start
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: start)
  }
  private func cancelFill(animated: Bool = false) {
    fillHold?.cancel()
    fillHold = nil
    if let circle = fillCircle {
      if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.3
        CATransaction.begin()
        CATransaction.setCompletionBlock { circle.removeFromSuperlayer() }
        CATransaction.setDisableActions(true)
        circle.opacity = 0
        circle.add(fade, forKey: "fade")
        CATransaction.commit()
      } else { circle.removeFromSuperlayer() }
      fillCircle = nil
      invalidate()
    }
  }
  private func pressure(_ event: NSEvent) -> CGFloat {
    event.pressure > 0 ? max(0.3, CGFloat(event.pressure)) : 1
  }
  override func mouseDragged(with event: NSEvent) {
    stopSelectionPulse()
    let v = convert(event.locationInWindow, from: nil)
    let p = imagePoint(v)
    if p.distance(to: start) * scale > 2 { tapCandidate = nil; cancelFill(animated: true) }
    if panning {
      pan = pan + (v - lastView)
      lastView = v
      needsDisplay = true
      return
    }
    hold?.cancel()
    if session.tool == .select, let a = originalAnnotation,
      let i = session.file.annotations.firstIndex(where: { $0.id == a.id })
    {
      var updated = a
      let dt = max(0.001, event.timestamp - lastDragTime)
      let step = p - imagePoint(lastView)
      let free = event.modifierFlags.contains(.option)
      let constrained = event.modifierFlags.contains(.shift)
      if let dragHandle {
        updated = selection(a).drag(dragHandle, from: start, to: p, constrained: constrained)
        if !free && !constrained && (dragHandle == .radial || dragHandle == .rotation) {
          let delta = updated.rotation - lastRotation
          lastRotation = updated.rotation
          updated.rotation = snapTool.update(velocity: delta / dt, delta: delta, updatedRotation: updated.rotation)
        }
      } else {
        let oldCenter = session.file.annotations[i].bounds.center
        let center = free ? a.bounds.center + (p - start) : snapTool.update(
          bounds: session.file.visibleRect, velocity: CGPoint(x: step.x / dt, y: step.y / dt),
          delta: step, updatedPosition: oldCenter + step, size: a.bounds.size)
        updated.translate(center - a.bounds.center)
      }
      if free { snapTool.reset(); snapTool.rotationReset() }
      lastView = v
      lastDragTime = event.timestamp
      session.file.annotations[i] = updated
      invalidate()
      return
    }
    if session.tool == .crop {
      cropDraft = rect(from: start, to: p, square: event.modifierFlags.contains(.shift))
        .intersection(session.file.imageBounds)
      needsDisplay = true
      return
    }
    guard var a = draft else { return }
    if a.tool.isBrush {
      guard let point = strokeInput.sample(at: p, time: event.timestamp) else { return }
      a.points.append(point.location)
      a.pressures.append(pressure(event))
      a.velocities?.append(point.velocity)
    } else if a.tool == .line {
      var end = p
      if event.modifierFlags.contains(.shift) {
        let angle = (start.angle(to: p) / (.pi / 4)).rounded() * (.pi / 4)
        end = start.pointAt(distance: start.distance(to: p), angle: angle)
      }
      a.points = [start, CGPoint.middle(p1: start, p2: end), end]
    } else {
      a.rect = rect(from: start, to: p, square: event.modifierFlags.contains(.shift))
    }
    draft = a
    if penPreviews[a.id] != nil {
      do { try renderer.updateStrokePreview(a, size: session.file.size) } catch { onError?(error) }
    }
    needsDisplay = true
    if a.tool == .pen && session.recognizesShapes {
      let work = DispatchWorkItem { [weak self] in self?.recognizeShape() }
      hold = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
  }
  private func rect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
    var d = b - a
    if square {
      let length = max(abs(d.x), abs(d.y))
      d = CGPoint(x: d.x < 0 ? -length : length, y: d.y < 0 ? -length : length)
    }
    return CGRect(x: min(a.x, a.x + d.x), y: min(a.y, a.y + d.y), width: abs(d.x), height: abs(d.y))
  }
  private func recognizeShape() {
    guard var a = draft, a.tool == .pen, a.points.count > 5 else { return }
    let b = a.rawBounds.insetBy(dx: a.lineWidth, dy: a.lineWidth)
    if a.points.first!.distance(to: a.points.last!) < max(20, min(b.width, b.height) * 0.3),
      min(b.width, b.height) > 20
    {
      let edgeCount = a.points.filter {
        min(abs($0.x - b.minX), abs($0.x - b.maxX), abs($0.y - b.minY), abs($0.y - b.maxY)) < min(
          b.width, b.height) * 0.09
      }.count
      a.tool = CGFloat(edgeCount) / CGFloat(a.points.count) > 0.75 ? .rectangle : .ellipse
      a.rect = b
      a.points = []
      a.pressures = []
      draft = a
      removePreview(a.id)
      needsDisplay = true
    } else {
      let first = a.points.first!
      let last = a.points.last!
      if first.distance(to: last) > 20
        && a.points.allSatisfy({
          $0.distance(to: $0.perpendicularPointOnLine(start: first, end: last)) < 12 / scale
        })
      {
        a.tool = .line
        a.points = [first, CGPoint.middle(p1: first, p2: last), last]
        a.arrowHeads = .none
        draft = a
        removePreview(a.id)
        needsDisplay = true
      }
    }
  }
  override func mouseUp(with event: NSEvent) {
    cancelFill(animated: true)
    hold?.cancel()
    if panning {
      panning = false
      return
    }
    if let old = original {
      snapTool.reset()
      snapTool.rotationReset()
      session.commit(session.file, name: "Transform Object", previous: old)
      original = nil
      originalAnnotation = nil
    }
    if let crop = cropDraft, crop.width > 4, crop.height > 4 {
      var file = session.file
      file.crop = crop.integral
      session.commit(file, name: "Crop")
      fit()
    }
    cropDraft = nil
    if let candidate = tapCandidate, let a = draft,
       imagePoint(convert(event.locationInWindow, from: nil)).distance(to: start) * scale <= 2 {
      tapCandidate = nil
      draft = nil
      removePreview(a.id)
      resumeBrush = a.tool
      session.tool = .select
      session.selectedID = candidate.id
      pulseSelection(candidate)
      return
    }
    tapCandidate = nil
    if var a = draft {
      if a.tool.isBrush {
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        if let point = strokeInput.sample(at: p, time: event.timestamp, ending: true) {
          a.points.append(point.location)
          a.pressures.append(pressure(event))
          a.velocities?.append(point.velocity)
          a.hasTerminalSample = true
        }
      }
      // AppKit can coalesce a quick mouse drag to only its two endpoints.
      // Supply one intermediate sample to the unmodified Telegram spline engine.
      if a.tool.isBrush, a.points.count == 2,
        a.points[0].distance(to: a.points[1]) > 16 / (a.inputZoom ?? 1)
      {
        a.points.insert(CGPoint.middle(p1: a.points[0], p2: a.points[1]), at: 1)
        if a.pressures.count == 2 {
          a.pressures.insert((a.pressures[0] + a.pressures[1]) / 2, at: 1)
        }
        if var velocities = a.velocities, velocities.count == 2 {
          velocities.insert(velocities.last!, at: 1)
          a.velocities = velocities
        }
        // Inserting a point invalidates the incremental spline. Attach a new
        // preview to the rebuilt source element, not to the discarded cache.
        removePreview(a.id)
        beginPreview(a)
      }
      draft = nil
      if a.tool.isBrush {
        do {
          if try renderer.isValidStroke(a, size: session.file.size) {
            session.add(a)
            penPreviews[a.id]?.finish()
          }
        } catch {
          onError?(error)
        }
      } else if !a.points.isEmpty || (a.rect.width > 1 && a.rect.height > 1) {
        session.add(a)
      }
    }
    invalidate()
  }
  override func keyDown(with event: NSEvent) {
    guard !event.modifierFlags.contains(.command) else {
      super.keyDown(with: event)
      return
    }
    if event.keyCode == 49 {
      spaceDown = true
      NSCursor.openHand.set()
      return
    }
    if event.keyCode == 51 || event.keyCode == 117 {
      session.deleteSelected()
      return
    }
    if event.keyCode == 53 {
      cancelFill()
      hold?.cancel()
      draft = nil
      cropDraft = nil
      if let old = original {
        snapTool.reset()
        snapTool.rotationReset()
        session.file = old
        original = nil
        originalAnnotation = nil
      }
      session.selectedID = nil
      invalidate()
      return
    }
    let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
    let delta: CGPoint?
    switch event.keyCode {
    case 123: delta = CGPoint(x: -step, y: 0)
    case 124: delta = CGPoint(x: step, y: 0)
    case 125: delta = CGPoint(x: 0, y: step)
    case 126: delta = CGPoint(x: 0, y: -step)
    default: delta = nil
    }
    if let delta {
      session.updateSelected(name: "Move Object") { $0.translate(delta) }
      return
    }
    if let key = event.charactersIgnoringModifiers?.lowercased(),
      let tool = MarkupTool.allCases.first(where: { $0.shortcut == key })
    {
      session.selectedID = nil
      session.tool = tool
      onToolChange?()
      return
    }
    super.keyDown(with: event)
  }
  override func keyUp(with event: NSEvent) {
    if event.keyCode == 49 {
      spaceDown = false
      NSCursor.arrow.set()
    } else {
      super.keyUp(with: event)
    }
  }
  func setZoom(_ value: CGFloat, at anchor: CGPoint) {
    let source = imagePoint(anchor)
    let actual = zoom / pixelScale
    zoom = min(max(8, actual), max(min(0.2, actual), value))
    pan = pan + (anchor - viewPoint(source))
  }
  func actualSize() { setZoom(zoom / pixelScale, at: editingBounds.center) }
  override func smartMagnify(with event: NSEvent) {
    if abs(pixelScale - 1) < 0.01 {
      fit()
    } else {
      setZoom(zoom / pixelScale, at: convert(event.locationInWindow, from: nil))
    }
  }
  override func magnify(with event: NSEvent) {
    setZoom(zoom * (1 + event.magnification), at: convert(event.locationInWindow, from: nil))
  }
  override func scrollWheel(with event: NSEvent) {
    if event.modifierFlags.contains(.command) {
      setZoom(
        zoom * exp(-event.scrollingDeltaY * 0.01), at: convert(event.locationInWindow, from: nil))
    } else {
      // AppKit has already applied the user’s system scrolling direction.
      let direction: CGFloat = session.markupPreferences.reversesScrollPan ? -1 : 1
      pan.x += direction * event.scrollingDeltaX
      pan.y += direction * event.scrollingDeltaY
      needsDisplay = true
    }
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      let url = urls.first
    {
      onDrop?(url, imagePoint(convert(sender.draggingLocation, from: nil)))
      return true
    }
    if let data = ImageCodec.pasteboardImage(sender.draggingPasteboard) {
      do {
        try insertSticker(data, at: imagePoint(convert(sender.draggingLocation, from: nil)))
        return true
      } catch { onError?(error) }
    }
    return false
  }
  func insertSticker(_ data: Data, at point: CGPoint? = nil) throws {
    inlineText?.onFinish?(true)
    let image = try ImageCodec.decode(data)
    let factor = min(1, session.file.visibleRect.width * 0.3 / (zoom * CGFloat(image.width)))
    let size = CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
    let center = point ?? insertionCenter
    var a = Annotation(tool: .sticker)
    a.imageData = try ImageCodec.encode(image, type: .png)
    a.rect = CGRect(
      x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
      height: size.height)
    session.add(a)
    session.selectedID = a.id
    session.tool = .select
  }
}

private final class StrokePreviewClip: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class EntityPreviewOverlay: NSView {
  weak var canvas: CanvasView?
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) {
    guard let canvas, let c = NSGraphicsContext.current?.cgContext else { return }
    c.saveGState()
    defer { c.restoreGState() }
    c.clip(to: canvas.viewport)
    let origin = canvas.viewPoint(.zero)
    c.translateBy(x: origin.x, y: origin.y)
    c.scaleBy(x: canvas.scale, y: canvas.scale)
    let elapsed = canvas.selectionStart.map { CGFloat(CACurrentMediaTime() - $0) }
    func scale(_ factor: CGFloat, around p: CGPoint) {
      c.translateBy(x: p.x, y: p.y)
      c.scaleBy(x: factor, y: factor)
      c.translateBy(x: -p.x, y: -p.y)
    }
    for a in canvas.session.file.annotations where !a.tool.isInk && canvas.hiddenTextID != a.id {
      c.saveGState()
      if a.id == canvas.session.selectedID, let t = elapsed {
        let factor = t < 0.1 ? 1 - 0.12 * t / 0.1 : 0.88 + 0.12 * min(1, (t - 0.1) / 0.2)
        scale(factor, around: a.bounds.center)
      }
      try? canvas.renderer.draw(a, file: canvas.session.file, in: c)
      c.restoreGState()
    }
    if let t = elapsed, let a = canvas.session.selected {
      c.setAlpha(min(1, max(0, (t - 0.1) / 0.2)))
      scale(0.88 + 0.12 * min(1, max(0, (t - 0.1) / 0.23)), around: a.bounds.center)
      TelegramEntitySelection(a, size: canvas.session.file.size, scale: canvas.scale)
        .draw(in: c, backingScale: canvas.backingScale)
    }
  }
}
