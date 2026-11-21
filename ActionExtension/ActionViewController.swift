import AppKit
import UniformTypeIdentifiers

@objc(ActionViewController)
final class ActionViewController: NSViewController {
  private var editor: EditorViewController?
  private var started = false
  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
    preferredContentSize = view.frame.size
  }
  override func viewDidAppear() {
    super.viewDidAppear()
    guard !started else { return }
    started = true
    guard let items = extensionContext?.inputItems as? [NSExtensionItem],
      let provider = items.flatMap({ $0.attachments ?? [] }).first(
        where: ExtensionTransport.canRead)
    else {
      fail(MarkupError.invalidImage)
      return
    }
    ExtensionTransport.load(provider) { [weak self] result in
      DispatchQueue.main.async {
        switch result {
        case .success(let file): self?.present(file)
        case .failure(let error): self?.fail(error)
        }
      }
    }
  }

  private func present(_ file: MarkupFile) {
    let editor = EditorViewController(session: EditorSession(file: file, preferences: .standard))
    editor.isExtension = true
    addChild(editor)
    editor.view.frame = view.bounds
    editor.view.autoresizingMask = [.width, .height]
    view.addSubview(editor.view)
    self.editor = editor
    editor.onExport = { [weak self] in self?.finish() }
    editor.onClose = { [weak self] in
      self?.extensionContext?.cancelRequest(
        withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
  }
  private func finish() {
    guard let editor else { return }
    do {
      let data = try ImageCodec.encode(
        editor.canvas.renderer.render(editor.session.file), type: .png)
      let provider = ExtensionTransport.provider(png: data)
      let item = NSExtensionItem()
      item.attachments = [provider]
      extensionContext?.completeRequest(returningItems: [item], completionHandler: nil)
    } catch { editor.show(error) }
  }
  private func fail(_ error: Error) { extensionContext?.cancelRequest(withError: error) }
}
