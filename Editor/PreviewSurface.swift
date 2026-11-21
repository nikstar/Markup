import AppKit

/// Keep the backdrop behind a plain content view so document pixels never participate in vibrancy.
class PreviewSurface: NSView {
  private let glass = NSGlassEffectView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    glass.frame = bounds
    glass.autoresizingMask = [.width, .height]
    glass.style = .regular
    glass.cornerRadius = 18
    addSubview(glass)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    glass.cornerRadius = window?.styleMask.contains(.fullScreen) == true ? 0 : 18
  }
}

/// AppKit handles title truncation, fullscreen, and overflow at smaller window sizes.
final class PreviewToolbar: NSToolbar, NSToolbarDelegate {
  private let controls: [NSButton]
  init(_ name: String, controls: [NSButton]) {
    self.controls = controls
    super.init(identifier: .init(name))
    displayMode = .iconOnly
    delegate = self
  }
  required init(coder: NSCoder) { fatalError() }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace] + controls.map { .init($0.accessibilityIdentifier()) }
  }
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }
  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
               willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    guard let button = controls.first(where: { $0.accessibilityIdentifier() == id.rawValue }) else { return nil }
    let item = NSToolbarItem(itemIdentifier: id)
    item.label = button.accessibilityLabel() ?? button.title
    item.toolTip = button.toolTip
    item.view = button
    if button.image == nil { item.visibilityPriority = .high }
    let menuItem = NSMenuItem(title: item.label, action: #selector(NSButton.performClick(_:)), keyEquivalent: "")
    // Route overflow through the same button. Share needs its view as the presentation anchor.
    menuItem.target = button
    item.menuFormRepresentation = menuItem
    return item
  }
}
