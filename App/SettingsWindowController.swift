import AppKit
import ServiceManagement
import Sparkle

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  private let preferences: MarkupPreferences
  private let updater: SPUUpdater
  private let updateChecks = NSSwitch()
  private let stack = NSStackView()
  private let history = NSSwitch()
  private let pan = NSPopUpButton()
  private let login = NSSwitch()
  private let loginItems = NSButton(title: "Allow Markup in Login Items…", target: nil, action: nil)

  init(updater: SPUUpdater, preferences: MarkupPreferences = MarkupPreferences()) {
    self.updater = updater
    self.preferences = preferences
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 414, height: 210),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Settings"
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    super.init(window: window)
    window.delegate = self

    history.target = self
    history.action = #selector(changeHistory)
    pan.addItems(withTitles: ["System default", "Reversed"])
    pan.target = self
    pan.action = #selector(changePan)
    updateChecks.target = self
    updateChecks.action = #selector(changeUpdateChecks)
    login.target = self
    login.action = #selector(changeLogin)
    loginItems.target = self
    loginItems.action = #selector(openLoginItems)
    loginItems.bezelStyle = .inline
    loginItems.controlSize = .small

    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    let content = window.contentView!
    content.addSubview(stack)
    for (index, row) in [
      setting("Keep edit history", detail: "Restore layers and undo steps when reopening an image.", control: history),
      setting("Pan direction", control: pan),
      setting("Automatically check for updates", control: updateChecks),
      setting("Launch at login", detail: "Start in the menu bar with screenshot monitoring.", control: login),
    ].enumerated() {
      if index > 0 {
        let rule = NSBox()
        rule.boxType = .separator
        stack.addArrangedSubview(rule)
        rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
      }
      stack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    stack.addArrangedSubview(loginItems)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
    ])
    refresh()
    window.center()
    NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                          name: NSApplication.didBecomeActiveNotification, object: nil)
  }
  required init?(coder: NSCoder) { fatalError() }

  private func setting(_ title: String, detail: String? = nil, control: NSControl) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    control.setAccessibilityLabel(title)
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    let line = NSStackView()
    line.distribution = .gravityAreas
    line.alignment = .centerY
    line.addView(label, in: .leading)
    line.addView(control, in: .trailing)
    guard let detail else { return line }
    let caption = NSTextField(labelWithString: detail)
    caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    caption.textColor = .secondaryLabelColor
    control.setAccessibilityHelp(detail)
    let row = NSStackView(views: [line, caption])
    row.orientation = .vertical
    row.alignment = .leading
    row.spacing = 1
    line.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
    return row
  }

  @objc private func changeHistory() { preferences.keepsEditHistory = history.state == .on }
  @objc private func changePan() { preferences.reversesScrollPan = pan.indexOfSelectedItem == 1 }
  @objc private func changeUpdateChecks() { updater.automaticallyChecksForUpdates = updateChecks.state == .on }
  @objc private func changeLogin() {
    do {
      let service = SMAppService.mainApp
      if login.state != .on {
        try service.unregister()
      } else if service.status == .requiresApproval {
        openLoginItems()
      } else {
        try service.register()
      }
    } catch {
      // A user may have disabled the item in System Settings since opening this window.
      if SMAppService.mainApp.status != .requiresApproval, let window {
        NSAlert(error: error).beginSheetModal(for: window)
      }
    }
    refresh()
  }
  @objc private func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

  func windowDidBecomeKey(_ notification: Notification) { refresh() }

  @objc private func refresh() {
    guard let window, let content = window.contentView else { return }
    updateChecks.state = updater.automaticallyChecksForUpdates ? .on : .off
    history.state = preferences.keepsEditHistory ? .on : .off
    pan.selectItem(at: preferences.reversesScrollPan ? 1 : 0)
    let status = SMAppService.mainApp.status
    login.state = status == .enabled ? .on : .off
    loginItems.isHidden = status != .requiresApproval
    content.layoutSubtreeIfNeeded()
    let height = ceil(stack.fittingSize.height) + 32
    if height != content.frame.height { window.setContentSize(NSSize(width: content.frame.width, height: height)) }
  }
}
