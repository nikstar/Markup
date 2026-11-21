import AVFoundation
import AppKit
import ScreenCaptureKit

@main struct Recording {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
      do {
        try await record()
        exit(0)
      } catch {
        print(error)
        exit(1)
      }
    }
    app.run()
  }
  @MainActor static func record() async throws {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    let dir = out.deletingLastPathComponent()
    let scenario = CommandLine.arguments[2]
    let file = try scenario == "zoom" ? zoomFixture() : SampleImage.file()
    let session = EditorSession(file: file)
    let vc = EditorViewController(session: session)
    let canvas = vc.canvas
    let window: NSWindow
    let shelf = scenario.hasPrefix("shelf")
    if scenario == "zoom" || shelf {
      window = MarkupWindow.editor(vc, title: shelf ? "Screenshot.png" : "Zoom test.png")
      if shelf {
        let dark = scenario == "shelf-dark"
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setFrame(CGRect(x: 40, y: 40, width: dark ? 960 : 748, height: 488), display: false)
      }
    } else {
      window = NSPanel(contentRect: CGRect(x: 40, y: 40, width: 1040, height: 660),
                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      window.contentViewController = vc
      window.setContentSize(CGSize(width: 1040, height: 660))
    }
    var gainedFocus = false
    let observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil, queue: .main
    ) { note in
      if let active = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        active.processIdentifier == ProcessInfo.processInfo.processIdentifier
      {
        gainedFocus = true
      }
    }
    defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }

    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    window.hidesOnDeactivate = false
    window.hasShadow = false
    window.orderBack(nil)
    vc.view.layoutSubtreeIfNeeded()
    session.tool = scenario == "zoom" || shelf ? .pen : .text
    vc.view.display()
    let content = try await SCShareableContent.currentProcess
    guard let own = content.windows.first(where: { $0.windowID == window.windowNumber }) else {
      throw NSError(domain: "own window missing", code: 1)
    }
    let filter = SCContentFilter(desktopIndependentWindow: own)
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width) * (shelf ? 2 : 1)
    config.height = Int(window.frame.height) * (shelf ? 2 : 1)
    config.showsCursor = false
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.ignoreShadowsSingleWindow = true
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    let settings = SCRecordingOutputConfiguration()
    settings.outputURL = out
    let delegate = RecorderDelegate()
    let output = SCRecordingOutput(configuration: settings, delegate: delegate)
    try stream.addRecordingOutput(output)
    try await stream.startCapture()
    for _ in 0..<100 where !delegate.started { try await Task.sleep(for: .milliseconds(20)) }
    guard delegate.started else { throw NSError(domain: "recording failed to start", code: 2) }
    func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: canvas.convert(p, to: nil), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    func pause(_ ms: Int) async throws {
      vc.view.layoutSubtreeIfNeeded()
      vc.view.displayIfNeeded()
      try await Task.sleep(for: .milliseconds(ms))
      precondition(
        NSWorkspace.shared.frontmostApplication?.processIdentifier
          != ProcessInfo.processInfo.processIdentifier)
    }
    if shelf {
      func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
      let views = descendants(vc.view)
      let panel = views.compactMap { $0 as? TelegramToolsPanel }.first!
      func button(_ id: String) -> NSButton {
        views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == id }!
      }
      func pointer(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        let point = CGPoint(x: x, y: panel.bounds.midY)
        if type == .mouseEntered || type == .mouseExited {
          return NSEvent.enterExitEvent(with: type, location: panel.convert(point, to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        return event(type, canvas.convert(point, from: panel))
      }
      let cell = panel.subviews[2]
      let x = cell.frame.midX
      try await pause(350)
      panel.mouseEntered(with: pointer(.mouseEntered, x))
      try await pause(320)
      cell.mouseDown(with: pointer(.leftMouseDown, x))
      cell.mouseUp(with: pointer(.leftMouseUp, x))
      precondition(session.tool == .marker)
      try await pause(360)
      for step in 1...12 {
        panel.mouseMoved(with: pointer(.mouseMoved, x + cell.frame.width * CGFloat(step) / 12))
        try await pause(16)
      }
      panel.mouseExited(with: pointer(.mouseExited, panel.bounds.maxX + 1))
      try await pause(290)
      button("mode_text").performClick(nil)
      try await pause(250)
      vc.editText(at: canvas.insertionCenter, annotation: nil)
      canvas.inlineText?.insertText("Look here", replacementRange: NSRange(location: NSNotFound, length: 0))
      try await pause(450)
      button("mode_draw").performClick(nil)
      precondition(session.tool == .marker && session.file.annotations.count == 1)
      try await pause(420)
      let black = views.compactMap { $0 as? SwatchButton }.first { !$0.isHiddenOrHasHiddenAncestor && $0.accessibilityLabel() == "Black" }!
      black.performClick(nil)
      precondition(black.chosen && session.color == InkColor(rgb: 0))
      let fit = button("fitCanvas")
      let controls = [black, button("addObject"), button("addSticker"), button("tool_crop"), fit]
      let frames = controls.map { $0.convert($0.bounds, to: vc.view) }
      precondition(fit.isHidden)
      try await pause(250)
      canvas.setZoom(0.85, at: canvas.editingBounds.center)
      try await pause(320)
      canvas.setZoom(0.8, at: canvas.editingBounds.center)
      try await pause(180)
      precondition(!fit.isHidden && fit.alphaValue == 1)
      fit.performClick(nil)
      try await pause(340)
      precondition(fit.isHidden && canvas.zoom == 1)
      // Reverse an unfinished fade twice, then reset at the end of the gesture.
      canvas.setZoom(1.08, at: canvas.editingBounds.center)
      try await pause(80)
      canvas.fit()
      try await pause(65)
      canvas.setZoom(1.1, at: canvas.editingBounds.center)
      try await pause(320)
      precondition(!fit.isHidden && fit.alphaValue == 1)
      canvas.fit()
      try await pause(320)
      precondition(fit.isHidden && frames == controls.map { $0.convert($0.bounds, to: vc.view) })
    } else if scenario == "zoom" {
      let anchor = canvas.editingBounds.center + CGPoint(x: 34, y: 8)
      let source = canvas.imagePoint(anchor)
      try await pause(300)
      for step in 1...30 {
        canvas.setZoom(1 + CGFloat(step) / 20, at: anchor)
        precondition(canvas.imagePoint(anchor).distance(to: source) < 0.001)
        try await pause(step == 2 ? 180 : 17)
      }
      try await pause(250)
      let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
      canvas.keyDown(with: space)
      canvas.mouseDown(with: event(.leftMouseDown, anchor))
      for step in 1...18 {
        canvas.mouseDragged(with: event(.leftMouseDragged, anchor + CGPoint(x: step * 8, y: 0)))
        try await pause(17)
      }
      canvas.mouseUp(with: event(.leftMouseUp, anchor + CGPoint(x: 144, y: 0)))
      canvas.keyUp(with: space)
      try await pause(250)
      canvas.fit()
      try await pause(300)
    } else if scenario == "text" {
      try await pause(250)
      let p = CGPoint(x: canvas.viewport.midX + 60, y: canvas.viewport.midY - 20)
      canvas.mouseDown(with: event(.leftMouseDown, p))
      canvas.mouseUp(with: event(.leftMouseUp, p))
      guard let editor = canvas.inlineText, window.firstResponder === editor else {
        fatalError("no insertion focus")
      }
      try await pause(350)
      for word in ["Check ", "this", "\n", "label"] {
        editor.insertText(word, replacementRange: NSRange(location: NSNotFound, length: 0))
        try await pause(160)
      }
      editor.setSelectedRange(NSRange(location: 6, length: 4))
      try await pause(200)
      editor.applyColor(InkColor(rgb: 0xf32e23))
      editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
      try await pause(200)
      for i in 1...8 {
        canvas.setZoom(1 + CGFloat(i) * 0.035, at: p)
        try await pause(32)
      }
      try await pause(180)
      vc.finishText()
      try await pause(320)
      let saved = session.selected!
      vc.editText(at: saved.rect.center, annotation: saved)
      if let text = canvas.inlineText {
        text.selectAll(nil)
        text.insertText("Discard", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await pause(380)
        text.cancelOperation(nil)
      }
      precondition(session.selected?.text == "Check this\nlabel")
      try await pause(320)
    } else if scenario == "controls" {
      var a = Annotation(tool: .text, rect: CGRect(x: 380, y: 250, width: 440, height: 70))
      a.text = "Check this"
      a.rotation = 0.65
      a.color = InkColor(rgb: 0xffffff)
      a.textStyle = .filled
      session.add(a)
      session.selectedID = a.id
      session.tool = .select
      try await pause(300)
      vc.editSelectedText()
      try await pause(540)
      vc.finishText()
      try await pause(550)
      session.updateSelected(name: "Straighten") { $0.rotation = 0 }
      vc.editSelectedText()
      try await pause(340)
      let slider = canvas.subviews.compactMap { $0 as? TelegramSizeSlider }.first!
      func slide(_ type: NSEvent.EventType, _ y: CGFloat) -> NSEvent {
        event(type, canvas.convert(CGPoint(x: 12, y: y), from: slider))
      }
      slider.mouseDown(with: slide(.leftMouseDown, 196))
      for i in 1...10 {
        slider.mouseDragged(with: slide(.leftMouseDragged, 196 - CGFloat(i) * 5))
        try await pause(27)
      }
      slider.mouseUp(with: slide(.leftMouseUp, 146))
      try await pause(290)
      vc.finishText()
      try await pause(370)
      vc.eyedropper()
      let sampler = canvas.subviews.compactMap { $0 as? EyedropperView }.last!
      try await pause(420)
      let target = canvas.viewPoint(CGPoint(x: 175, y: 358))
      for i in 1...8 {
        let f = CGFloat(i) / 8
        sampler.update(
          at: canvas.viewport.center
            + CGPoint(
              x: (target.x - canvas.viewport.midX) * f, y: (target.y - canvas.viewport.midY) * f))
        try await pause(35)
      }
      sampler.finish(true)
      try await pause(290)
      session.selectedID = nil
      session.tool = .pen
      session.color = InkColor(rgb: 0x3e809d)
      let press = canvas.viewPoint(CGPoint(x: 280, y: 520))
      canvas.mouseDown(with: event(.leftMouseDown, press))
      try await pause(890)
      canvas.mouseUp(with: event(.leftMouseUp, press))
      try await pause(200)
      session.undo.undo()
      var shape = Annotation(
        tool: .rectangle, rect: CGRect(x: 370, y: 420, width: 280, height: 140))
      shape.filled = true
      shape.color = InkColor(rgb: 0xce3453)
      session.add(shape)
      session.tool = .pen
      session.selectedID = nil
      let tap = canvas.viewPoint(shape.rect.center)
      canvas.mouseDown(with: event(.leftMouseDown, tap))
      canvas.mouseUp(with: event(.leftMouseUp, tap))
      precondition(session.selectedID == shape.id)
      try await pause(410)
      let start = canvas.viewPoint(shape.rect.center)
      canvas.mouseDown(with: event(.leftMouseDown, start))
      for i in 1...18 {
        let p = canvas.viewPoint(shape.rect.center + CGPoint(x: CGFloat(i) * 4.5, y: 0))
        canvas.mouseDragged(with: event(.leftMouseDragged, p))
        try await pause(32)
      }
      canvas.mouseUp(
        with: event(.leftMouseUp, canvas.viewPoint(shape.rect.center + CGPoint(x: 81, y: 0))))
      try await pause(460)
    } else {
      let picker = TelegramColorPicker(color: InkColor(rgb: 0x0161fd))
      picker.view.frame = CGRect(x: 325, y: 55, width: 400, height: 550)
      vc.view.addSubview(picker.view)
      try await pause(250)
      func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
      let views = descendants(picker.view)
      let field = views.compactMap { $0 as? TelegramColorField }.first!
      let modes = views.compactMap { $0 as? NSSegmentedControl }.first!
      for mode in 0...2 {
        modes.selectedSegment = mode
        _ = modes.sendAction(modes.action, to: modes.target)
        if mode < 2 {
          let local = field.convert(CGPoint(x: 200, y: 156), to: nil)
          let click = NSEvent.mouseEvent(
            with: .leftMouseDown, location: local, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 0)!
          field.mouseDown(with: click)
        }
        try await pause(300)
      }
      let percent = views.compactMap { $0 as? NSTextField }.first {
        $0.accessibilityLabel() == "Opacity percent"
      }!
      percent.stringValue = "65"
      _ = percent.sendAction(percent.action, to: percent.target)
      precondition(picker.color.alpha == 0.65)
      try await pause(200)
      picker.view.removeFromSuperview()
      session.tool = .pen
      let button = descendants(vc.view).compactMap { $0 as? TelegramFastColorButton }.first!
      let start = canvas.convert(
        CGPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
      button.mouseDown(with: event(.leftMouseDown, start))
      try await pause(800)
      guard
        let spectrum = window.contentView?.subviews.compactMap({ $0 as? TelegramColorField }).first
      else { fatalError("Missing quick spectrum") }
      for i in 1...9 {
        let local = CGPoint(x: CGFloat(i) * 27, y: CGFloat(10 - i) * 20)
        button.mouseDragged(with: event(.leftMouseDragged, canvas.convert(local, from: spectrum)))
        try await pause(32)
      }
      button.mouseUp(with: event(.leftMouseUp, start))
      try await pause(420)
      precondition(spectrum.superview == nil)
    }
    try await stream.stopCapture()
    for _ in 0..<100 where !delegate.ended { try await Task.sleep(for: .milliseconds(25)) }
    guard delegate.ended else { throw NSError(domain: "recording failed to finalize", code: 3) }
    print("Recorded background window", own.windowID, "to", dir.path)
    precondition(!gainedFocus)
    print("Recorder activations: 0")
    window.orderOut(nil)
  }
  // Repeated fine detail reveals where the blur begins. Wide color bands expose any break
  // in the image as it moves under the two stationary toolbars.
  private static func zoomFixture() throws -> MarkupFile {
    let context = try ImageCodec.context(width: 1200, height: 800)
    let colors: [UInt32] = [0x344b73, 0x2c786e, 0xc87e53, 0xa45165, 0x645a89]
    for (index, color) in colors.enumerated() {
      let left = index * 240
      context.setFillColor(NSColor(rgb: color).cgColor)
      context.fill(CGRect(x: left, y: 0, width: 240, height: 800))
      for line in 0..<30 {
        context.setFillColor(NSColor.white.withAlphaComponent(line.isMultiple(of: 4) ? 0.58 : 0.29).cgColor)
        context.fill(CGRect(x: left + line * 8, y: 0, width: 3, height: 800))
      }
    }
    return try MarkupFile.importing(ImageCodec.encode(context.makeImage()!, type: .png))
  }

}
final class RecorderDelegate: NSObject, SCRecordingOutputDelegate {
  var started = false
  var ended = false
  func recordingOutputDidStartRecording(_ output: SCRecordingOutput) { started = true }
  func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) { ended = true }
  func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) { print(error) }
}
