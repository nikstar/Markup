import AppKit
import UniformTypeIdentifiers

enum MarkupWindow {
  static func make(title: String, size: CGSize, resizable: Bool, on screen: NSScreen? = nil) -> NSWindow {
    var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    if resizable { style.insert(.resizable) }
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: style, backing: .buffered, defer: false, screen: screen)
    window.title = title
    window.isOpaque = false
    window.backgroundColor = .clear
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.toolbarStyle = .unifiedCompact
    window.isReleasedWhenClosed = false
    return window
  }

  static let welcomeSize = CGSize(width: 372, height: 224)
  static func welcome(open: @escaping () -> Void, files: @escaping (URL) -> Void,
                      image: @escaping (Data, String) -> Void) -> NSWindow {
    let window = make(title: "Markup", size: welcomeSize, resizable: true)
    let drop = WelcomeDropView(frame: CGRect(origin: .zero, size: welcomeSize))
    drop.onOpen = open
    drop.receiver = ImageDrop(file: files, image: image)
    window.contentView = drop
    window.titleVisibility = .hidden
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(kind)?.isHidden = true
    }
    window.minSize = welcomeSize
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.setFrame(CGRect(origin: window.frame.origin, size: welcomeSize), display: false)
    window.isMovableByWindowBackground = true
    window.center()
    return window
  }

  static let minimumEditorSize = CGSize(width: 396, height: 424)
  static func editorSize(image: CGSize, available: CGSize, backingScale: CGFloat, titleHeight: CGFloat) -> CGSize {
    let limit = CGSize(width: max(minimumEditorSize.width, available.width - 24),
                       height: max(minimumEditorSize.height, available.height - 24))
    // A landscape image has room for the single-row shelf. Portraits can use the narrower arrangement.
    let preferredWidth: CGFloat = image.width >= image.height ? 748 : minimumEditorSize.width
    func fitted(shelfHeight: CGFloat) -> CGSize {
      let chrome = titleHeight + shelfHeight
      let area = CGSize(width: limit.width, height: limit.height - chrome)
      let scale = CanvasView.fitScale(image: image, area: area, backingScale: backingScale)
      let width = ceil(image.width * scale) + CanvasView.fitPadding.width
      let height = ceil(image.height * scale) + CanvasView.fitPadding.height + chrome
      return CGSize(width: min(available.width, limit.width, max(preferredWidth, width)),
                    height: min(available.height, limit.height, max(minimumEditorSize.height, height)))
    }
    let wideHeight = EditorToolShelf.height(for: EditorToolShelf.singleRowWidth)
    let size = fitted(shelfHeight: wideHeight)
    let shelfHeight = EditorToolShelf.height(for: size.width)
    return shelfHeight == wideHeight ? size : fitted(shelfHeight: shelfHeight)
  }

  static func editor(_ editor: EditorViewController, title: String) -> NSWindow {
    let screen = NSScreen.main
    let available = screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
    let window = make(title: title, size: CGSize(width: 748, height: 500), resizable: true, on: screen)
    window.contentViewController = editor
    window.toolbar = editor.documentToolbar()
    let size = editorSize(image: editor.session.file.visibleRect.size, available: available,
                          backingScale: screen?.backingScaleFactor ?? 1,
                          titleHeight: window.frame.height - window.contentLayoutRect.height)
    window.minSize = CGSize(width: min(available.width, minimumEditorSize.width),
                            height: min(available.height, minimumEditorSize.height))
    window.setFrame(CGRect(origin: window.frame.origin, size: size), display: false)
    return window
  }
}

final class WelcomeDropView: PreviewSurface {
  var onOpen: (() -> Void)?
  fileprivate var receiver: ImageDrop?
  private let highlight = NSBox()
  let openButton = NSButton(title: "Open Image…", target: nil, action: nil)
  override init(frame: CGRect) {
    super.init(frame: frame)
    registerForDraggedTypes(ImageDrop.types)
    func windowButton(_ symbol: String, title: String, action: Selector) -> NSButton {
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
      let b = NSButton(image: image, target: self, action: action)
      b.isBordered = false
      b.contentTintColor = .secondaryLabelColor
      b.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
      b.setAccessibilityLabel(title)
      b.toolTip = title
      b.widthAnchor.constraint(equalToConstant: 20).isActive = true
      b.heightAnchor.constraint(equalToConstant: 26).isActive = true
      return b
    }
    let close = windowButton("xmark.circle.fill", title: "Close", action: #selector(closeWindow))
    let expand = windowButton("arrow.up.right.and.arrow.down.left.circle.fill", title: "Toggle Full Screen",
                              action: #selector(expandWindow))
    let name = NSTextField(labelWithString: "Markup")
    name.font = .systemFont(ofSize: 13, weight: .semibold)
    name.textColor = .labelColor
    let leading = NSStackView(views: [close, expand, name])
    leading.spacing = 0
    leading.setCustomSpacing(5, after: expand)
    leading.translatesAutoresizingMaskIntoConstraints = false
    addSubview(leading)
    openButton.target = self
    openButton.action = #selector(openFile)
    openButton.bezelStyle = .push
    openButton.borderShape = .capsule
    openButton.setAccessibilityIdentifier("openImage")
    openButton.setAccessibilityLabel("Open Image")
    openButton.toolTip = "Open an image (⌘O)"
    openButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(openButton)
    NSLayoutConstraint.activate([
      leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      leading.centerYAnchor.constraint(equalTo: topAnchor, constant: 19),
      openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
      openButton.centerYAnchor.constraint(equalTo: leading.centerYAnchor),
    ])
    let icon = NSImageView()
    icon.image = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)
    icon.symbolConfiguration = .init(pointSize: 28, weight: .regular)
    icon.contentTintColor = .secondaryLabelColor
    let prompt = NSTextField(labelWithString: "Drop an image here")
    prompt.font = .systemFont(ofSize: 15, weight: .medium)
    prompt.textColor = .labelColor
    let stack = NSStackView(views: [icon, prompt])
    stack.orientation = .vertical
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    highlight.boxType = .custom
    highlight.borderWidth = 2
    highlight.borderColor = .controlAccentColor
    highlight.fillColor = .clear
    highlight.cornerRadius = 13
    highlight.titlePosition = .noTitle
    highlight.isHidden = true
    highlight.translatesAutoresizingMaskIntoConstraints = false
    addSubview(highlight, positioned: .below, relativeTo: stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 16),
      highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      highlight.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func closeWindow() { window?.performClose(nil) }
  @objc private func expandWindow() { window?.toggleFullScreen(nil) }
  @objc func openFile() { onOpen?() }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let operation = ImageDrop.operation(sender.draggingPasteboard, allowed: sender.draggingSourceOperationMask)
    highlight.isHidden = operation.isEmpty
    return operation
  }
  override func draggingExited(_ sender: NSDraggingInfo?) { highlight.isHidden = true }
  override func draggingEnded(_ sender: NSDraggingInfo) { highlight.isHidden = true }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    highlight.isHidden = true
    return openDrop(sender.draggingPasteboard)
  }
  func openDrop(_ board: NSPasteboard) -> Bool {
    receiver?.open(board) ?? false
  }
}
