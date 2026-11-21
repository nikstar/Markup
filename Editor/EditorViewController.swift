import AppKit
import UniformTypeIdentifiers

final class EditorViewController: NSViewController {
  let session: EditorSession
  let canvas: CanvasView
  var onExport: (() -> Void)?
  var onClose: (() -> Void)?
  var onSave: (() -> Void)?
  var onOpen: (() -> Void)?
  var onCapture: (() -> Void)?
  var isExtension = false
  private let toolTitle = NSTextField(labelWithString: "Pen")
  private let sizeValue = NSTextField(labelWithString: "8 px")
  private let colorWell = NSColorWell()
  private let widthSlider = NSSlider(value: 8, minValue: 1, maxValue: 100, target: nil, action: nil)
  private let opacitySlider = NSSlider(
    value: 1, minValue: 0.05, maxValue: 1, target: nil, action: nil)
  private let fontSizeSlider = NSSlider(
    value: 48, minValue: 12, maxValue: 180, target: nil, action: nil)
  private let fillToggle = NSButton(checkboxWithTitle: "Fill shape", target: nil, action: nil)
  private let recognition = NSButton(
    checkboxWithTitle: "Hold to perfect a shape", target: nil, action: nil)
  private let stylePopup = NSPopUpButton()
  private let fontPopup = NSPopUpButton()
  private let alignmentPopup = NSPopUpButton()
  private let headsPopup = NSPopUpButton()
  private let toolPopup = NSPopUpButton()
  private var documentActions: [NSButton] = []
  private var resetCropButton: NSButton!
  private var undoButton: NSButton!
  private var redoButton: NSButton!
  private var clearButton: NSButton!
  private var textControls: NSStackView!
  var onTextSnapshotChange: (() -> Void)?
  var onPendingTextChange: ((Bool) -> Void)?
  private var pendingText = false
  private var activeInk: InkColor { canvas.inlineText?.selectedInk ?? session.selected?.color ?? session.color }
  private var activeAnnotation: Annotation? { canvas.inlineText?.annotation ?? session.selected }
  private var palette: NSStackView!
  private weak var sampler: EyedropperView?
  private var colorPopover: NSPopover?
  private var sourceSwatches: [SwatchButton] = []
  private var sourceText = TelegramTextSettings(frame: .zero)
  private var sourceTools = TelegramToolsPanel(frame: .zero)
  private weak var inspector: NSScrollView?
  private var canvasTrailing: NSLayoutConstraint!
  private let inspectorWidth: CGFloat = 232
  private let objectControls = NSStackView()
  private let objectStyle = NSButton()
  private let objectFlip = NSButton()
  private let colorButton = TelegramFastColorButton(frame: .zero)
  private let sizeSlider = TelegramSizeSlider(frame: .zero)
  private var beforeAdjustment: MarkupFile?
  private var drawMode: NSButton!
  private var textMode: NSButton!
  private var updating = false
  private var sharePicker: NSSharingServicePicker?

  init(session: EditorSession) {
    self.session = session
    canvas = CanvasView(session: session)
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() {
    view = PreviewSurface(frame: CGRect(x: 0, y: 0, width: 960, height: 680))
    // Paint the full window. Fit and editing gestures use only the space between the controls.
    canvas.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(canvas)
    let area = canvas.editingGuide
    canvas.addLayoutGuide(area)
    documentActions = makeActions()
    var top = view.safeAreaLayoutGuide.topAnchor
    if isExtension {
      let header = row([spacer()] + documentActions, spacing: 12)
      header.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
      header.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(header)
      NSLayoutConstraint.activate([
        header.topAnchor.constraint(equalTo: top),
        header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      ])
      top = header.bottomAnchor
    }
    let inspector = inspectorView()
    self.inspector = inspector
    inspector.isHidden = true
    inspector.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(inspector)
    let bottom = bottomBar()
    bottom.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bottom)
    canvasTrailing = canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    NSLayoutConstraint.activate([
      canvas.topAnchor.constraint(equalTo: view.topAnchor),
      canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor), canvasTrailing,
      canvas.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
      area.topAnchor.constraint(equalTo: top),
      area.bottomAnchor.constraint(equalTo: bottom.topAnchor),
      area.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
      area.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
      area.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
      inspector.topAnchor.constraint(equalTo: area.topAnchor),
      inspector.bottomAnchor.constraint(equalTo: area.bottomAnchor),
      inspector.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      inspector.widthAnchor.constraint(equalToConstant: inspectorWidth),
      bottom.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    sizeSlider.translatesAutoresizingMaskIntoConstraints = false
    canvas.addSubview(sizeSlider)
    NSLayoutConstraint.activate([
      sizeSlider.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
      sizeSlider.centerYAnchor.constraint(equalTo: area.centerYAnchor),
      sizeSlider.widthAnchor.constraint(equalToConstant: 30),
      sizeSlider.heightAnchor.constraint(equalToConstant: 240),
    ])
    sizeSlider.began = { [weak self] in self?.beginAdjustment() }
    sizeSlider.updated = { [weak self] in self?.adjustSize($0) }
    sizeSlider.released = { [weak self] in
      self?.endAdjustment(name: "Change Size")
      self?.canvas.brushPreview = nil
    }
    canvas.onDrawingChanged = { [weak self] in self?.refresh() }
    canvas.onText = { [weak self] p, a in self?.editText(at: p, annotation: a) }
    canvas.onSticker = { [weak self] p in self?.stickerMenu(at: p) }
    canvas.onEntityMenu = { [weak self] in self?.entityMenu(for: $0) ?? NSMenu() }
    canvas.onDrop = { [weak self] url, point in
      do { try self?.canvas.insertSticker(Data(contentsOf: url), at: point) } catch { self?.show(error) }
    }
    canvas.onToolChange = { [weak self] in self?.refresh() }
    canvas.onError = { [weak self] in self?.show($0) }
    session.onChange = { [weak self] in
      self?.canvas.invalidate()
      self?.refresh()
    }
    refresh()
  }
  override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.makeFirstResponder(canvas.inlineText ?? canvas)
  }
  override var undoManager: UndoManager? { session.undo }
  private func button(_ title: String, _ symbol: String?, _ action: Selector, id: String? = nil)
    -> NSButton
  {
    let b = NSButton(title: title, target: self, action: action)
    b.bezelStyle = .rounded
    if let symbol {
      b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }
    if let id { b.setAccessibilityIdentifier(id) }
    b.toolTip = title
    return b
  }
  private func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.init(1), for: .horizontal)
    return v
  }
  private func row(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.spacing = spacing
    s.alignment = .centerY
    return s
  }
  private func label(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = .systemFont(ofSize: 11, weight: .semibold)
    f.textColor = .secondaryLabelColor
    return f
  }
  func documentToolbar() -> NSToolbar {
    loadViewIfNeeded()
    return PreviewToolbar("MarkupDocument", controls: documentActions)
  }
  private func makeActions() -> [NSButton] {
    func icon(_ title: String, _ symbol: String, _ action: Selector, _ id: String) -> NSButton {
      let b = button(title, symbol, action, id: id)
      b.imagePosition = .imageOnly
      b.isBordered = false
      b.setAccessibilityLabel(title)
      return b
    }
    undoButton = icon("Undo", "arrow.uturn.backward", #selector(undoEdit), "undo")
    undoButton.toolTip = "Undo (⌘Z)"
    redoButton = icon("Redo", "arrow.uturn.forward", #selector(redoEdit), "redo")
    clearButton = icon("Clear annotations", "trash", #selector(clearAnnotations), "clearAnnotations")
    var actions = [undoButton!, redoButton!, clearButton!,
                   icon("Properties", "slider.horizontal.3", #selector(toggleInspector), "Properties"),
                   icon("Copy", "doc.on.doc", #selector(copyImage), "copyImage")]
    if isExtension {
      actions.insert(button("Cancel", nil, #selector(closeEditor), id: "cancel"), at: 0)
    } else {
      actions.insert(icon("Open", "folder", #selector(openImage), "openImage"), at: 0)
      actions.insert(icon("Capture", "camera.viewfinder", #selector(captureImage), "captureImage"), at: 1)
      actions.append(icon("Share", "square.and.arrow.up", #selector(shareImage(_:)), "shareImage"))
    }
    actions.append(button(isExtension ? "Done" : "Save", nil, #selector(finishEditing),
                          id: isExtension ? "done" : "saveImage"))
    return actions
  }
  private func inspectorView() -> NSScrollView {
    let content = FlippedStackView()
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 13
    content.edgeInsets = NSEdgeInsets(top: 20, left: 18, bottom: 18, right: 18)
    toolTitle.font = .systemFont(ofSize: 21, weight: .bold)
    content.addArrangedSubview(toolTitle)
    toolPopup.addItems(withTitles: MarkupTool.allCases.map(\.title))
    toolPopup.target = self
    toolPopup.action = #selector(selectToolPopup)
    toolPopup.setAccessibilityIdentifier("toolPicker")
    content.addArrangedSubview(toolPopup)
    resetCropButton = button("Reset Crop", "crop", #selector(resetCrop), id: "resetCrop")
    content.addArrangedSubview(resetCropButton)
    palette = row([], spacing: 5)
    for (i, color) in InkColor.palette.enumerated() {
      let b = SwatchButton(color: color.ns)
      b.tag = i
      b.target = self
      b.action = #selector(selectColor(_:))
      b.widthAnchor.constraint(equalToConstant: 17).isActive = true
      b.heightAnchor.constraint(equalToConstant: 24).isActive = true
      b.setAccessibilityLabel(
        ["White", "Black", "Coral", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink"][i])
      palette.addArrangedSubview(b)
    }
    content.addArrangedSubview(label("COLOR"))
    content.addArrangedSubview(palette)
    colorWell.color = session.color.ns
    colorWell.target = self
    colorWell.action = #selector(changeColor)
    colorWell.widthAnchor.constraint(equalToConstant: 116).isActive = true
    colorWell.heightAnchor.constraint(equalToConstant: 26).isActive = true
    content.addArrangedSubview(
      row([colorWell, button("Pick", "eyedropper", #selector(eyedropper))]))
    content.addArrangedSubview(row([label("SIZE"), spacer(), sizeValue]))
    widthSlider.target = self
    widthSlider.action = #selector(changeWidth)
    widthSlider.isContinuous = false
    widthSlider.setAccessibilityLabel("Brush size")
    content.addArrangedSubview(widthSlider)
    content.addArrangedSubview(label("OPACITY"))
    opacitySlider.target = self
    opacitySlider.action = #selector(changeOpacity)
    opacitySlider.isContinuous = false
    opacitySlider.setAccessibilityLabel("Opacity")
    content.addArrangedSubview(opacitySlider)
    fillToggle.target = self
    fillToggle.action = #selector(changeFill)
    content.addArrangedSubview(fillToggle)
    headsPopup.addItems(withTitles: ["No arrowheads", "One arrowhead", "Two arrowheads"])
    headsPopup.target = self
    headsPopup.action = #selector(changeHeads)
    content.addArrangedSubview(headsPopup)
    textControls = NSStackView()
    textControls.orientation = .vertical
    textControls.alignment = .leading
    textControls.spacing = 8
    textControls.addArrangedSubview(label("TEXT"))
    fontPopup.addItems(withTitles: [
      "HelveticaNeue-Bold", "HelveticaNeue", "Georgia-Bold", "Menlo-Bold", "AvenirNext-Heavy",
      "Noteworthy-Bold", "AppleColorEmoji",
    ])
    fontPopup.target = self
    fontPopup.action = #selector(changeFontPopup)
    textControls.addArrangedSubview(fontPopup)
    textControls.addArrangedSubview(button("More fonts…", nil, #selector(chooseFont)))
    stylePopup.addItems(withTitles: TextStyle.allCases.map { $0.rawValue.capitalized })
    stylePopup.target = self
    stylePopup.action = #selector(changeStyle)
    textControls.addArrangedSubview(stylePopup)
    alignmentPopup.addItems(withTitles: ["Align left", "Align center", "Align right"])
    alignmentPopup.target = self
    alignmentPopup.action = #selector(changeAlignment)
    textControls.addArrangedSubview(alignmentPopup)
    fontSizeSlider.target = self
    fontSizeSlider.action = #selector(changeFontSize)
    fontSizeSlider.isContinuous = false
    fontSizeSlider.setAccessibilityLabel("Font size")
    textControls.addArrangedSubview(fontSizeSlider)
    textControls.addArrangedSubview(
      button("Edit text…", nil, #selector(editSelectedText), id: "editText"))
    content.addArrangedSubview(textControls)
    content.addArrangedSubview(label("OBJECT"))
    content.addArrangedSubview(
      row([
        button("Duplicate", nil, #selector(duplicateObject), id: "duplicateObject"),
        button("Delete", nil, #selector(deleteObject), id: "deleteObject"),
      ]))
    content.addArrangedSubview(
      row([
        button("Rotate", "rotate.right", #selector(rotateObject)),
        button(
          "Flip", "arrow.left.and.right.righttriangle.left.righttriangle.right",
          #selector(flipObject)),
      ]))
    content.addArrangedSubview(
      row([
        button("To front", nil, #selector(bringFront)), button("To back", nil, #selector(sendBack)),
      ]))
    recognition.state = .on
    recognition.target = self
    recognition.action = #selector(changeRecognition)
    recognition.font = .systemFont(ofSize: 11)
    content.addArrangedSubview(recognition)
    let hint = NSTextField(
      wrappingLabelWithString:
        "Drag to draw. Hold ⇧ for straight lines or equal sides.\n\nV to select · Delete to remove\nSpace + drag to pan\nPinch or ⌘ scroll to zoom"
    )
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .tertiaryLabelColor
    content.addArrangedSubview(hint)
    let scroll = NSScrollView()
    scroll.contentView = FlippedClipView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = content
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
      content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
    ])
    for v in [
      toolPopup, widthSlider, opacitySlider, fontPopup, stylePopup, alignmentPopup, fontSizeSlider,
    ] { v.widthAnchor.constraint(equalToConstant: 194).isActive = true }
    return scroll
  }
  private func bottomBar() -> NSView {
    let instruments = NSView()
    // All modes share one slot. Hiding a control never reflows its neighbors.
    for control in [sourceTools as NSView, sourceText, objectControls] {
      control.translatesAutoresizingMaskIntoConstraints = false
      instruments.addSubview(control)
      NSLayoutConstraint.activate([
        control.centerXAnchor.constraint(equalTo: instruments.centerXAnchor),
        control.centerYAnchor.constraint(equalTo: instruments.centerYAnchor),
      ])
    }
    NSLayoutConstraint.activate([
      sourceTools.widthAnchor.constraint(equalTo: instruments.widthAnchor),
      sourceTools.heightAnchor.constraint(equalTo: instruments.heightAnchor),
    ])
    sourceTools.pressed = { [weak self] key in
      guard let self else { return }
      self.finishText()
      self.session.selectedID = nil
      self.session.tool = MarkupTool(key)
      self.view.window?.makeFirstResponder(self.canvas)
    }
    sourceTools.resized = { [weak self] _, size in
      self?.session.setBrushSize(size)
      self?.canvas.brushPreview = size
    }
    sourceTools.released = { [weak self] in self?.canvas.brushPreview = nil }
    sourceText.onStyle = { [weak self] style in
      guard let self else { return }
      self.session.textStyle = style
      self.updateText(name: "Text Style") { $0.textStyle = style }
      self.refresh()
    }
    sourceText.onAlignment = { [weak self] alignment in
      guard let self else { return }
      self.session.alignment = alignment
      self.updateText(name: "Text Alignment") { $0.alignment = alignment }
      self.refresh()
    }
    sourceText.onFont = { [weak self] font in
      guard let self else { return }
      self.session.fontName = font
      self.updateText(name: "Text Font") {
        $0.fontName = font
      }
      self.refresh()
    }
    sourceText.onEdit = { [weak self] in
      guard let self else { return }
      if self.canvas.inlineText != nil { self.finishText() } else { self.editSelectedText() }
    }
    sourceText.onCancel = { [weak self] in self?.finishText(apply: false) }
    objectControls.orientation = .horizontal
    objectControls.alignment = .centerY
    objectControls.spacing = 14
    objectControls.heightAnchor.constraint(equalToConstant: 80).isActive = true
    for (control, action) in [(objectStyle, #selector(cycleObjectStyle)), (objectFlip, #selector(flipObject))] {
      control.target = self
      control.action = action
      control.isBordered = false
      control.imagePosition = .imageOnly
      control.widthAnchor.constraint(equalToConstant: 44).isActive = true
      control.heightAnchor.constraint(equalToConstant: 44).isActive = true
      objectControls.addArrangedSubview(control)
    }
    objectFlip.image = artwork("shapeFlip", size: 30)
    objectFlip.setAccessibilityLabel("Flip")
    objectFlip.toolTip = "Flip"
    sourceText.isHidden = true
    for (i, color) in InkColor.shelfPalette.enumerated() {
      let b = SwatchButton(color: color.ink.ns)
      sourceSwatches.append(b)
      b.tag = i
      b.target = self
      b.action = #selector(selectSourceColor(_:))
      b.widthAnchor.constraint(equalToConstant: 24).isActive = true
      b.heightAnchor.constraint(equalToConstant: 24).isActive = true
      b.setAccessibilityLabel(color.name)
      b.toolTip = color.name
    }
    colorButton.target = self
    colorButton.action = #selector(openColors(_:))
    colorButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
    colorButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
    colorButton.began = { [weak self] in self?.beginAdjustment() }
    colorButton.changed = { [weak self] in self?.applyColor($0) }
    colorButton.ended = { [weak self] in self?.endAdjustment(name: "Change Color") }
    func shelfButton(_ label: String, _ symbol: String, _ action: Selector, _ id: String) -> NSButton {
      let b = button(label, symbol, action, id: id)
      b.imagePosition = .imageOnly
      b.isBordered = false
      b.setAccessibilityLabel(label)
      b.image = b.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
      b.widthAnchor.constraint(equalToConstant: 28).isActive = true
      b.heightAnchor.constraint(equalToConstant: 28).isActive = true
      return b
    }
    func column(_ views: [NSView], spacing: CGFloat) -> NSStackView {
      let stack = NSStackView(views: views)
      stack.orientation = .vertical
      stack.spacing = spacing
      stack.alignment = .centerX
      return stack
    }
    let shapes = shelfButton("Shapes and selection", "square.on.circle", #selector(addMenu(_:)), "addObject")
    let colors = NSGridView(views: [
      [colorButton] + Array(sourceSwatches.prefix(4)),
      Array(sourceSwatches.dropFirst(4)),
    ])
    colors.xPlacement = .center
    colors.yPlacement = .center
    colors.columnSpacing = 3
    colors.column(at: 0).trailingPadding = 5
    colors.rowSpacing = 0
    for index in 0..<colors.numberOfRows { colors.row(at: index).height = 28 }

    drawMode = ShelfModeButton("Draw", symbol: "pencil.tip", id: "mode_draw", target: self, action: #selector(selectMode(_:)))
    textMode = ShelfModeButton("Text", symbol: "textformat", id: "mode_text", target: self, action: #selector(selectMode(_:)))
    let sticker = shelfButton("Stickers", "face.smiling", #selector(openStickers(_:)), "addSticker")
    let crop = shelfButton("Crop", "crop", #selector(selectCrop), "tool_crop")
    crop.menu = NSMenu()
    crop.menu?.addItem(withTitle: "Reset Crop", action: #selector(resetCrop), keyEquivalent: "").target = self
    let fit = shelfButton("Fit to Window", "arrow.up.left.and.down.right.magnifyingglass", #selector(fitCanvas), "fitCanvas")
    fit.toolTip = "Fit to Window (⌘0)"
    let fitSlot = FitButtonSlot(button: fit)
    canvas.onZoomChanged = { [weak fitSlot] zoom in fitSlot?.update(zoom: zoom) }
    fitSlot.update(zoom: canvas.zoom)
    let actions = row([column([drawMode!, textMode!], spacing: 2), shapes, sticker, crop, fitSlot], spacing: 6)
    return EditorToolShelf(colors: colors, instruments: instruments, actions: actions)
  }
  override func viewWillLayout() {
    super.viewWillLayout()
    layoutInspector()
  }
  private func layoutInspector() {
    guard let inspector, !inspector.isHidden else {
      canvasTrailing?.constant = 0
      return
    }
    let overlaysCanvas = view.bounds.width < 380 + inspectorWidth
    inspector.drawsBackground = overlaysCanvas
    canvasTrailing.constant = overlaysCanvas ? 0 : -inspectorWidth
  }
  @objc private func toggleInspector() {
    inspector?.isHidden.toggle()
    layoutInspector()
  }
  @objc private func selectObjects() {
    finishText()
    session.tool = .select
    session.selectedID = nil
    view.window?.makeFirstResponder(canvas)
  }
  @objc private func selectCrop() {
    finishText()
    session.tool = .crop
    session.selectedID = nil
    view.window?.makeFirstResponder(canvas)
  }
  @objc private func openColors(_ sender: NSButton) {
    sampler?.finish(false)
    let picker = TelegramColorPicker(color: activeInk)
    picker.sampleImage = { [weak self] in self?.eyedropper() }
    picker.updated = { [weak self] in self?.applyColor($0) }
    let popover = NSPopover()
    popover.contentViewController = picker
    popover.behavior = .transient
    popover.contentSize = CGSize(width: 400, height: 550)
    colorPopover = popover
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }
  @objc private func selectSourceColor(_ sender: NSButton) {
    applyColor(InkColor.shelfPalette[sender.tag].ink)
  }
  @objc private func selectMode(_ sender: NSButton) {
    if sender === textMode, let text = canvas.inlineText {
      refresh()
      view.window?.makeFirstResponder(text)
      return
    }
    finishText()
    session.selectedID = nil
    session.tool = sender === textMode ? .text : MarkupTool(session.drawingState.selectedTool)
    refresh()
    view.window?.makeFirstResponder(canvas)
  }
  @objc private func openStickers(_ sender: NSButton) {
    finishText()
    stickerMenu(at: canvas.insertionCenter, from: sender)
  }
  @objc private func addMenu(_ sender: NSButton) {
    let menu = NSMenu()
    menu.addItem(withTitle: "Select Objects", action: #selector(selectObjects), keyEquivalent: "").target = self
    menu.addItem(.separator())
    for (name, tool, heads) in [
      ("Rectangle", MarkupTool.rectangle, ArrowHeads.none), ("Ellipse", .ellipse, .none),
      ("Speech bubble", .bubble, .none), ("Star", .star, .none), ("Arrow", .line, .end),
      ("Double arrow", .line, .both), ("Line", .line, .none), ("Pixelate", .pixelate, .none),
      ("Redact", .redact, .none), ("Fill canvas", .fill, .none),
    ] {
      let item = NSMenuItem(title: name, action: #selector(insertShape(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = [tool.rawValue, heads.rawValue]
      let icons: [MarkupTool: String] = [.rectangle: "shapeRectangle", .ellipse: "shapeEllipse", .bubble: "shapeBubble", .star: "shapeStar", .line: "shapeArrow"]
      if let icon = icons[tool] { item.image = artwork(icon, size: 22) }
      menu.addItem(item)
    }
    menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY), in: sender)
  }
  @objc private func insertShape(_ sender: NSMenuItem) {
    finishText()
    guard let values = sender.representedObject as? [String],
      let tool = MarkupTool(rawValue: values[0]), let heads = ArrowHeads(rawValue: values[1])
    else { return }
    session.selectedID = nil
    session.tool = tool
    session.arrowHeads = heads
    if tool.isVector || tool == .line {
      let center = canvas.insertionCenter
      let width = round(session.file.size.width * 0.5) / canvas.zoom
      var a = session.makeAnnotation(at: center)
      let height = tool == .star ? width : round(width * (tool == .bubble ? 0.7 : 0.75))
      a.rect = CGRect(
        x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
      if tool == .bubble { a.bubbleTail = CGPoint(x: 0.16, y: height * 0.18) }
      if tool == .line {
        a.points = [
          CGPoint(x: center.x - width / 2, y: center.y), center,
          CGPoint(x: center.x + width / 2, y: center.y),
        ]
        a.vectorMid = CGPoint(x: 0.5, y: 0)
        a.vectorWidth = 0.3
      }
      if tool != .line {
        a.shapeWidth = 0.15
        a.lineWidth = TelegramShapeGeometry.lineWidth(a, size: session.file.size)
      }
      session.add(a)
      session.selectedID = a.id
      session.tool = .select
    }
    view.window?.makeFirstResponder(canvas)
  }
  func refresh() {
    guard isViewLoaded else { return }
    updating = true
    defer { updating = false }
    sourceTools.update(
      state: session.drawingState, selected: session.tool.telegramKey, animated: true)
    let selected = activeAnnotation
    let tool = canvas.inlineText != nil ? .text : selected?.tool ?? session.tool
    drawMode.state = tool == .text ? .off : .on
    textMode.state = tool == .text ? .on : .off
    let hasStyle = [.rectangle, .ellipse, .star, .bubble, .line].contains(tool)
    let hasFlip = [.sticker, .bubble].contains(tool)
    objectControls.isHidden = selected == nil || !(hasStyle || hasFlip)
    objectStyle.isHidden = !hasStyle
    objectFlip.isHidden = !hasFlip
    let sizeAvailable = tool == .text || hasStyle && (tool == .line || selected?.filled != true) || tool.telegramKey != nil
    sizeSlider.isHidden = !sizeAvailable || canvas.draft != nil
    if tool == .text {
      let limits = textSizeRange()
      sizeSlider.value = min(1, max(0, ((selected?.fontSize ?? session.fontSize) - limits.lowerBound) / max(1, limits.upperBound - limits.lowerBound)))
    } else if hasStyle, let selected {
      sizeSlider.value = min(1, max(0, selected.shapeWidth ?? selected.telegramVector(size: session.file.size).lineWidth))
    } else { sizeSlider.value = selected?.brushSize ?? session.drawingState.currentToolState.size ?? 0.5 }
    if !objectControls.isHidden, let selected {
      let label = tool == .line ? "Arrowheads: " + selected.arrowHeads.rawValue : selected.filled ? "Filled" : "Outline"
      objectStyle.image = artwork(selected.filled ? "shapeFill" : "shapeStroke", size: 30)
      objectStyle.setAccessibilityLabel(label)
      objectStyle.toolTip = label
    }
    sourceTools.isHidden = tool == .text || !objectControls.isHidden
    sourceText.isHidden = tool != .text
    sourceText.isEditing = canvas.inlineText != nil
    sourceText.update(
      style: selected?.textStyle ?? session.textStyle,
      alignment: selected?.alignment ?? session.alignment,
      font: selected?.fontName ?? session.fontName)
    toolTitle.stringValue = tool.title
    toolPopup.selectItem(at: MarkupTool.allCases.firstIndex(of: session.tool)!)

    colorButton.color = activeInk
    colorWell.color = activeInk.ns
    for (i, b) in sourceSwatches.enumerated() {
      b.chosen = InkColor.shelfPalette[i].ink == activeInk
    }
    widthSlider.doubleValue = Double(selected?.lineWidth ?? session.width)
    sizeValue.stringValue = "\(Int(widthSlider.doubleValue)) px"
    opacitySlider.doubleValue = Double(selected?.opacity ?? session.opacity)
    fillToggle.state = (selected?.filled ?? session.filled) ? .on : .off
    headsPopup.selectItem(
      at: ArrowHeads.allCases.firstIndex(of: selected?.arrowHeads ?? session.arrowHeads)!)
    headsPopup.isHidden = tool != .line
    fillToggle.isHidden = ![.rectangle, .ellipse, .star, .bubble].contains(tool)
    textControls.isHidden = tool != .text && tool != .sticker
    let face = selected?.fontName ?? session.fontName
    if !fontPopup.itemTitles.contains(face) { fontPopup.addItem(withTitle: face) }
    fontPopup.selectItem(withTitle: face)
    stylePopup.selectItem(
      at: TextStyle.allCases.firstIndex(of: selected?.textStyle ?? session.textStyle)!)
    alignmentPopup.selectItem(
      at: TextAlignment.allCases.firstIndex(of: selected?.alignment ?? session.alignment)!)
    let fontSize = selected?.fontSize ?? session.fontSize
    fontSizeSlider.minValue = min(fontSize, textSizeRange().lowerBound)
    fontSizeSlider.maxValue = max(fontSize, textSizeRange().upperBound)
    fontSizeSlider.doubleValue = fontSize
    resetCropButton.isHidden = session.file.crop == nil
    clearButton.isHidden = canvas.inlineText != nil
    clearButton.isEnabled = !session.file.annotations.isEmpty
    undoButton.isEnabled = (canvas.inlineText?.undoManager ?? session.undo).canUndo
    redoButton.isEnabled = (canvas.inlineText?.undoManager ?? session.undo).canRedo
  }
  @objc func selectToolButton(_ sender: NSButton) {
    finishText()
    session.tool = MarkupTool.allCases[sender.tag]
    session.selectedID = nil
    view.window?.makeFirstResponder(canvas)
  }
  @objc func selectToolPopup() {
    finishText()
    session.tool = MarkupTool.allCases[toolPopup.indexOfSelectedItem]
    session.selectedID = nil
    view.window?.makeFirstResponder(canvas)
  }
  @objc func selectColor(_ sender: NSButton) { applyColor(InkColor.palette[sender.tag]) }
  private func applyColor(_ c: InkColor) {
    session.color = c
    if let editor = canvas.inlineText {
      editor.applyColor(c)
      if colorPopover?.isShown != true { view.window?.makeFirstResponder(editor) }
    } else {
      updateText(name: "Change Color") { $0.color = c; $0.textColors = nil }
    }
    refresh()
  }
  @objc func changeColor() { if !updating { applyColor(InkColor(colorWell.color)) } }
  @objc func eyedropper() {
    colorPopover?.close()
    guard sampler == nil else { return }
    do {
      let image = try canvas.renderer.render(session.file, hiddenStrokeIDs: Set([canvas.inlineText?.annotation.id].compactMap { $0 }))
      let picker = try EyedropperView(canvas: canvas, image: image)
      sampler = picker
      picker.completed = { [weak self] color in
        guard let self else { return }
        self.sampler = nil
        if let color { self.applyColor(color) }
        self.view.window?.makeFirstResponder(self.canvas.inlineText ?? self.canvas)
      }
      canvas.addSubview(picker)
      view.window?.makeFirstResponder(picker)
      picker.appear()
    } catch { show(error) }
  }
  @objc func changeWidth() {
    session.width = widthSlider.doubleValue
    session.updateSelected(name: "Change Width") {
      $0.lineWidth = session.width
      if $0.tool.telegramKey != nil {
        $0.brushSize = TelegramBrushMetrics.value(
          $0.tool, size: session.file.size, width: session.width)
      }
      if $0.tool == .line { $0.vectorWidth = nil }
      $0.shapeWidth = nil
    }
    refresh()
  }
  @objc func changeOpacity() {
    session.opacity = opacitySlider.doubleValue
    updateText(name: "Change Opacity") { $0.opacity = session.opacity }
  }
  @objc func changeFill() {
    session.filled = fillToggle.state == .on
    session.updateSelected(name: "Change Fill") { $0.filled = session.filled }
  }
  @objc func changeHeads() {
    session.arrowHeads = ArrowHeads.allCases[headsPopup.indexOfSelectedItem]
    session.updateSelected(name: "Change Arrowheads") { $0.arrowHeads = session.arrowHeads }
  }
  @objc func changeStyle() {
    session.textStyle = TextStyle.allCases[stylePopup.indexOfSelectedItem]
    updateText(name: "Change Text Style") { $0.textStyle = session.textStyle }
  }
  @objc func changeFontPopup() {
    session.fontName = fontPopup.titleOfSelectedItem!
    updateText(name: "Change Font") {
      $0.fontName = session.fontName
    }
  }
  @objc func chooseFont() {
    let manager = NSFontManager.shared
    manager.target = self
    manager.setSelectedFont(
      NSFont(
        name: activeAnnotation?.fontName ?? session.fontName,
        size: activeAnnotation?.fontSize ?? session.fontSize) ?? .systemFont(ofSize: 48),
      isMultiple: false)
    manager.orderFrontFontPanel(self)
  }
  @objc func changeFont(_ sender: NSFontManager) {
    let font = sender.convert(
      NSFont(
        name: activeAnnotation?.fontName ?? session.fontName,
        size: activeAnnotation?.fontSize ?? session.fontSize) ?? .systemFont(ofSize: 48))
    session.fontName = font.fontName
    session.fontSize = font.pointSize
    if !fontPopup.itemTitles.contains(font.fontName) { fontPopup.addItem(withTitle: font.fontName) }
    updateText(name: "Change Font") {
      $0.fontName = font.fontName
      $0.fontSize = font.pointSize
    }
    refresh()
  }
  @objc func changeAlignment() {
    session.alignment = TextAlignment.allCases[alignmentPopup.indexOfSelectedItem]
    updateText(name: "Change Alignment") { $0.alignment = session.alignment }
  }
  @objc func changeFontSize() {
    session.fontSize = fontSizeSlider.doubleValue
    updateText(name: "Change Font Size") {
      $0.fontSize = session.fontSize
    }
  }
  @objc func changeRecognition() { session.recognizesShapes = recognition.state == .on }
  @objc func undoEdit() {
    (canvas.inlineText?.undoManager ?? session.undo).undo()
    refresh()
  }
  @objc func redoEdit() {
    (canvas.inlineText?.undoManager ?? session.undo).redo()
    refresh()
  }
  func entityMenu(for a: Annotation) -> NSMenu {
    let menu = NSMenu()
    func add(_ title: String, _ action: Selector) {
      menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }
    if a.tool == .text || a.tool == .sticker && a.imageData == nil { add("Edit Text", #selector(editSelectedText)) }
    if a.tool == .sticker || a.tool == .bubble { add("Flip", #selector(flipObject)) }
    if session.file.paintOrder.last(where: { session.file.separatesInk != true || $0.tool.isInk == a.tool.isInk })?.id != a.id { add("Bring to Front", #selector(bringFront)) }
    add("Duplicate", #selector(duplicateObject))
    add("Delete", #selector(deleteObject))
    return menu
  }
  @objc func clearAnnotations() {
    finishText()
    var file = session.file
    file.annotations.removeAll()
    session.commit(file, name: "Clear Annotations")
  }
  @objc func duplicateObject() { finishText(); session.duplicateSelected() }
  @objc func deleteObject() { finishText(); session.deleteSelected() }
  @objc func rotateObject() {
    session.updateSelected(name: "Rotate Object") { $0.rotation += .pi / 12 }
  }
  private func artwork(_ name: String, size: CGFloat) -> NSImage? {
    guard let url = Bundle(for: Self.self).url(forResource: name, withExtension: "png"),
          let image = NSImage(contentsOf: url) else { return nil }
    image.size = CGSize(width: size, height: size)
    image.isTemplate = true
    return image
  }
  @objc func cycleObjectStyle() {
    session.updateSelected(name: "Change Shape Style") { a in
      if a.tool == .line {
        a.arrowHeads = a.arrowHeads == .end ? .both : a.arrowHeads == .both ? .none : .end
      } else { a.filled.toggle() }
    }
  }
  private func textSizeRange() -> ClosedRange<CGFloat> {
    let dimension = max(session.file.size.width, session.file.size.height)
    let scale = activeAnnotation?.textScale ?? 1
    return min(4096, max(1, max(10, dimension * 0.025) * scale))...min(4096, max(1, max(10, dimension * 0.25) * scale))
  }
  private func beginAdjustment() {
    if canvas.inlineText == nil, session.selected != nil { beforeAdjustment = session.file }
  }
  private func endAdjustment(name: String) {
    guard let before = beforeAdjustment else { return }
    beforeAdjustment = nil
    session.commit(session.file, name: name, previous: before)
  }
  private func adjustSize(_ value: CGFloat) {
    if activeAnnotation?.tool == .text || canvas.inlineText != nil || session.tool == .text {
      let range = textSizeRange()
      let size = range.lowerBound + value * (range.upperBound - range.lowerBound)
      session.fontSize = size / (activeAnnotation?.textScale ?? 1)
      updateText(name: "Text Size") { $0.fontSize = size }
    } else if var a = session.selected, let index = session.file.annotations.firstIndex(where: { $0.id == a.id }) {
      if a.tool.isBrush {
        a.brushSize = value
        a.lineWidth = TelegramBrushMetrics.width(a.tool, size: session.file.size, value: value)
      } else {
        if a.tool == .line { a.vectorWidth = value }
        a.shapeWidth = value
        a.lineWidth = TelegramShapeGeometry.lineWidth(a, size: session.file.size)
      }
      session.file.annotations[index] = a
      session.onChange?()
    } else {
      session.setBrushSize(value)
      canvas.brushPreview = value
    }
  }
  @objc func flipObject() {
    session.updateSelected(name: "Flip Object") { a in
      if a.tool == .bubble {
        var tail = a.bubbleTail ?? CGPoint(x: 0.16, y: a.rect.height * 0.3)
        tail.x = 1 - tail.x
        a.bubbleTail = tail
      } else { a.flipped.toggle() }
    }
  }
  @objc func bringFront() { reorder(front: true) }
  @objc func sendBack() { reorder(front: false) }
  private func reorder(front: Bool) {
    guard let a = session.selected else { return }
    var file = session.file
    file.annotations.removeAll { $0.id == a.id }
    file.annotations.insert(a, at: front ? file.annotations.count : 0)
    session.commit(file, name: "Reorder Object")
  }
  @objc func fitCanvas() { canvas.fit() }
  @objc func resetCrop() {
    var file = session.file
    file.crop = nil
    session.commit(file, name: "Reset Crop")
    canvas.fit()
  }
  @objc func openImage() { onOpen?() }
  @objc func captureImage() { onCapture?() }
  @objc func closeEditor() { onClose?() }
  @objc func finishEditing() { finishText(); if isExtension { onExport?() } else { onSave?() } }
  @objc func copyImage() { writeEditedImage(to: .general) }
  func writeEditedImage(to board: NSPasteboard) {
    do {
      let image = try canvas.renderer.render(fileIncludingText)
      let png = try ImageCodec.encode(image, type: .png)
      board.clearContents()
      board.setData(png, forType: .png)
      if board === NSPasteboard.general {
        NSAccessibility.post(element: view, notification: .announcementRequested,
                             userInfo: [.announcement: "Copied edited image", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
      }
    } catch { show(error) }
  }
  @objc func paste(_ sender: Any?) {
    if let data = ImageCodec.pasteboardImage(.general) {
      do { try canvas.insertSticker(data) } catch { show(error) }
    }
  }
  @objc func shareImage(_ sender: NSButton) {
    do {
      let image = try canvas.renderer.render(fileIncludingText)
      sharePicker = NSSharingServicePicker(items: [NSImage(cgImage: image, size: .zero)])
      sharePicker?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    } catch { show(error) }
  }
  func show(_ error: Error) {
    let alert = NSAlert(error: error)
    if let window = view.window { alert.beginSheetModal(for: window) }
  }
  @objc func editSelectedText() {
    if let text = canvas.inlineText { view.window?.makeFirstResponder(text); return }
    if let a = session.selected, a.tool == .text || a.tool == .sticker && a.imageData == nil {
      editText(at: a.rect.origin, annotation: a)
    } else {
      editText(at: canvas.insertionCenter, annotation: nil)
    }
  }
  private func updateText(name: String, _ change: (inout Annotation) -> Void) {
    if let editor = canvas.inlineText {
      editor.updateStyle(change)
      view.window?.makeFirstResponder(editor)
    } else {
      func edit(_ a: inout Annotation) {
        let previousSize = a.fontSize
        let previousFont = a.fontName
        change(&a)
        if a.imageData == nil, [.text, .sticker].contains(a.tool),
           a.fontSize != previousSize || a.fontName != previousFont {
          let center = a.rect.center
          a.rect.size = TelegramTextLayout(a).fittedSize(
            maxWidth: max(a.rect.width, session.file.visibleRect.width * 0.9), minimumWidth: 224 * (a.textScale ?? 1))
          a.rect.origin = CGPoint(x: center.x - a.rect.width / 2, y: center.y - a.rect.height / 2)
        }
      }
      if beforeAdjustment != nil, let i = session.file.annotations.firstIndex(where: { $0.id == session.selectedID }) {
        var a = session.file.annotations[i]
        edit(&a)
        session.file.annotations[i] = a
        session.onChange?()
      } else { session.updateSelected(name: name, edit) }
    }
    refresh()
  }

  func editText(at point: CGPoint, annotation: Annotation?) {
    guard view.window != nil else { return }
    finishText()
    if annotation == nil { session.tool = .text }
    session.selectedID = annotation?.id
    var a = annotation ?? session.makeAnnotation(at: point)
    if annotation == nil {
      a.tool = .text
      a.textScale = 1 / canvas.zoom
      a.fontSize = max(1, min(4096, a.fontSize / canvas.zoom))
    }
    let editor = InlineTextView(annotation: a, existing: annotation != nil,
                                imageBounds: session.file.visibleRect, zoom: canvas.zoom)
    if !isExtension { editor.onCopyEditedImage = { [weak self] in self?.copyImage() } }
    editor.onImagePaste = { [weak self, weak editor] data in
      guard let self, let editor else { return }
      let center = editor.annotation.rect.center
      do {
        _ = try ImageCodec.decode(data)
        self.finishText(apply: false)
        try self.canvas.insertSticker(data, at: center)
      } catch { self.show(error) }
    }
    editor.onSelectionChange = { [weak self] in self?.refresh() }
    editor.onFinish = { [weak self] apply in self?.finishText(apply: apply) }
    editor.onUpdate = { [weak self] in
      guard let self else { return }
      guard let text = self.canvas.inlineText else { return }
      self.canvas.refreshTextBackdrop()
      self.setPendingText(text.original.map { $0 != text.annotation } ?? !text.string.isEmpty)
      self.onTextSnapshotChange?()
      self.refresh()
    }
    canvas.presentText(editor)
    refresh()
  }
  private func setPendingText(_ pending: Bool) {
    guard pendingText != pending else { return }
    pendingText = pending
    onPendingTextChange?(pending)
  }
  var fileIncludingText: MarkupFile { includingOpenCaption(in: session.file) }
  func includingOpenCaption(in base: MarkupFile) -> MarkupFile {
    var file = base
    guard let editor = canvas.inlineText else { return file }
    let a = editor.annotation
    if let index = file.annotations.firstIndex(where: { $0.id == a.id }) {
      if a.text.isEmpty { file.annotations.remove(at: index) } else { file.annotations[index] = a }
    } else if !a.text.isEmpty { file.annotations.append(a) }
    return file
  }
  func finishText(apply: Bool = true) {
    guard let editor = canvas.inlineText else { return }
    if editor.hasMarkedText() { editor.unmarkText() }
    let next = fileIncludingText
    let id = editor.annotation.id
    // Keep the outgoing caption above the dimmer until it fades. The document
    // already has the final payload when the next Save, Undo or Copy arrives.
    let returning = apply ? next.annotations.first { $0.id == id } : editor.original
    setPendingText(false)
    if apply {
      session.commit(next, name: editor.original == nil ? "Add Text" : editor.string.isEmpty ? "Delete Text" : "Edit Text")
    }
    canvas.dismissText(returning: returning)
    onTextSnapshotChange?()
    if session.file.annotations.contains(where: { $0.id == id }) {
      session.tool = .select
      session.selectedID = id
    }
    view.window?.makeFirstResponder(canvas)
    refresh()
  }

  private var stickerPoint = CGPoint.zero
  private func stickerMenu(at p: CGPoint, from button: NSButton? = nil) {
    stickerPoint = p
    let menu = NSMenu()
    for emoji in ["😀", "😍", "👍", "❤️", "🔥", "⭐️", "✅", "❌", "💡", "🎉", "👀", "📍"] {
      let item = NSMenuItem(title: emoji, action: #selector(addEmoji(_:)), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let item = NSMenuItem(
      title: "Import image sticker…", action: #selector(importSticker), keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    if let button {
      menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.maxY), in: button)
    } else {
      menu.popUp(positioning: nil, at: canvas.viewPoint(p), in: canvas)
    }
  }
  @objc private func addEmoji(_ sender: NSMenuItem) {
    var a = Annotation(tool: .sticker)
    a.text = sender.title
    a.fontName = "AppleColorEmoji"
    a.fontSize = 100 / canvas.zoom
    let size = TelegramTextLayout(a).fittedSize(maxWidth: a.fontSize * 3, minimumWidth: a.fontSize)
    a.rect = CGRect(x: stickerPoint.x - size.width / 2, y: stickerPoint.y - size.height / 2,
                    width: size.width, height: size.height)
    session.add(a)
    session.selectedID = a.id
    session.tool = .select
  }
  @objc func importSticker() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    guard let window = view.window else { return }
    panel.beginSheetModal(for: window) { [weak self] result in
      guard result == .OK, let url = panel.url, let self else { return }
      do { try self.canvas.insertSticker(Data(contentsOf: url)) } catch { self.show(error) }
    }
  }
}

/// A permanent slot keeps the shelf anchored throughout the button's fade.
private final class FitButtonSlot: NSView {
  private let button: NSButton
  private var showing = false
  private var transition = 0

  init(button: NSButton) {
    self.button = button
    super.init(frame: .zero)
    wantsLayer = true
    button.translatesAutoresizingMaskIntoConstraints = false
    addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: leadingAnchor),
      button.trailingAnchor.constraint(equalTo: trailingAnchor),
      button.topAnchor.constraint(equalTo: topAnchor),
      button.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    button.alphaValue = 0
    button.isHidden = true
  }
  required init?(coder: NSCoder) { fatalError() }

  func update(zoom: CGFloat) {
    let visible = abs(zoom - 1) > 0.000001
    guard visible != showing else { return }
    showing = visible
    transition += 1
    let revision = transition
    let opacity: CGFloat = visible ? 1 : 0
    button.setAccessibilityElement(visible)
    if window?.isVisible != true || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      button.alphaValue = opacity
      button.isHidden = !visible
      return
    }
    button.isHidden = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      button.animator().alphaValue = opacity
    } completionHandler: { [weak self] in
      guard let self, transition == revision else { return }
      button.isHidden = !visible
    }
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    showing ? super.hitTest(point) : nil
  }
}

private final class ShelfModeButton: NSButton {
  init(_ name: String, symbol: String, id: String, target: AnyObject, action: Selector) {
    super.init(frame: .zero)
    title = name
    self.target = target
    self.action = action
    setButtonType(.toggle)
    isBordered = false
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    imagePosition = .imageLeading
    imageHugsTitle = true
    font = .systemFont(ofSize: 12, weight: .medium)
    setAccessibilityIdentifier(id)
    setAccessibilityLabel(name)
    widthAnchor.constraint(equalToConstant: 70).isActive = true
    heightAnchor.constraint(equalToConstant: 24).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }

  override func draw(_ dirtyRect: NSRect) {
    if state == .on || isHighlighted {
      NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.18 : 0.11).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0.5), xRadius: 7, yRadius: 7).fill()
    }
    super.draw(dirtyRect)
  }
}

final class SwatchButton: NSButton {
  let ink: NSColor
  var chosen = false { didSet { needsDisplay = true } }
  init(color: NSColor) {
    ink = color
    super.init(frame: .zero)
    isBordered = false
    title = ""
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ dirtyRect: NSRect) {
    let disk = NSBezierPath(ovalIn: bounds.insetBy(dx: chosen ? 5 : 2, dy: chosen ? 5 : 2))
    ink.setFill()
    disk.fill()
    let neutral = ink.saturationComponent == 0
    NSColor.labelColor.withAlphaComponent(neutral ? 0.4 : 0.13).setStroke()
    disk.lineWidth = neutral ? 1 : 0.5
    disk.stroke()
    if chosen {
      let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
      path.lineWidth = 2
      (neutral ? NSColor.labelColor.withAlphaComponent(0.72) : ink).setStroke()
      path.stroke()
    }
  }
}

private final class FlippedStackView: NSStackView { override var isFlipped: Bool { true } }
private final class FlippedClipView: NSClipView { override var isFlipped: Bool { true } }

/// Keep the instrument slot at the bottom center in every editing mode.
final class EditorToolShelf: NSView {
  static let singleRowWidth: CGFloat = 716
  static func height(for width: CGFloat) -> CGFloat { width < singleRowWidth ? 140 : 80 }

  private let colorWidth: CGFloat
  private let actionWidth: CGFloat
  private var gap: NSLayoutConstraint!
  private var compact = [NSLayoutConstraint]()
  private var singleRow = [NSLayoutConstraint]()

  init(colors: NSGridView, instruments: NSView, actions: NSStackView) {
    colorWidth = colors.fittingSize.width
    actionWidth = actions.fittingSize.width
    super.init(frame: .zero)
    for group in [colors, instruments, actions] {
      group.translatesAutoresizingMaskIntoConstraints = false
      addSubview(group)
    }
    let upperRow = NSLayoutGuide(), leftGap = NSLayoutGuide(), rightGap = NSLayoutGuide()
    for guide in [upperRow, leftGap, rightGap] { addLayoutGuide(guide) }
    gap = rightGap.widthAnchor.constraint(equalToConstant: 32)
    NSLayoutConstraint.activate([
      instruments.widthAnchor.constraint(equalToConstant: 264),
      instruments.heightAnchor.constraint(equalToConstant: 80),
      instruments.centerXAnchor.constraint(equalTo: centerXAnchor),
      instruments.bottomAnchor.constraint(equalTo: bottomAnchor),
      colors.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
      rightGap.trailingAnchor.constraint(equalTo: actions.leadingAnchor),
      gap,
    ])
    compact = [
      colors.centerYAnchor.constraint(equalTo: instruments.topAnchor, constant: -28),
      upperRow.leadingAnchor.constraint(equalTo: colors.leadingAnchor),
      upperRow.trailingAnchor.constraint(equalTo: actions.trailingAnchor),
      upperRow.centerXAnchor.constraint(equalTo: centerXAnchor),
      rightGap.leadingAnchor.constraint(equalTo: colors.trailingAnchor),
    ]
    singleRow = [
      colors.centerYAnchor.constraint(equalTo: instruments.centerYAnchor),
      leftGap.leadingAnchor.constraint(equalTo: colors.trailingAnchor),
      leftGap.trailingAnchor.constraint(equalTo: instruments.leadingAnchor),
      leftGap.widthAnchor.constraint(equalTo: rightGap.widthAnchor),
      rightGap.leadingAnchor.constraint(equalTo: instruments.trailingAnchor),
    ]
    NSLayoutConstraint.activate(compact)
    setContentHuggingPriority(.required, for: .vertical)
    setContentCompressionResistancePriority(.required, for: .vertical)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: Self.height(for: bounds.width))
  }
  override func setFrameSize(_ newSize: NSSize) {
    let wasCompact = bounds.width < Self.singleRowWidth
    super.setFrameSize(newSize)
    let isCompact = newSize.width < Self.singleRowWidth
    let room = isCompact ? newSize.width - colorWidth - actionWidth - 24
      : (newSize.width - 264) / 2 - max(colorWidth, actionWidth) - 12
    gap.constant = max(8, min(32, room))
    if wasCompact != isCompact {
      NSLayoutConstraint.deactivate(wasCompact ? compact : singleRow)
      NSLayoutConstraint.activate(isCompact ? compact : singleRow)
      invalidateIntrinsicContentSize()
    }
  }
}
