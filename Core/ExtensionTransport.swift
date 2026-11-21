import AppKit
import UniformTypeIdentifiers

// Shared by the Action extension and tests, without depending on Telegram or a host app.
enum ExtensionTransport {
  static func canRead(_ provider: NSItemProvider) -> Bool {
    provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
      || provider.canLoadObject(ofClass: NSURL.self)
  }
  static func load(
    _ provider: NSItemProvider, completion: @escaping (Result<MarkupFile, Error>) -> Void
  ) {
    if let type = provider.registeredTypeIdentifiers.first(where: {
      UTType($0)?.conforms(to: .image) == true
    }) {
      provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
        do {
          if let error { throw error }
          guard let data else { throw MarkupError.invalidImage }
          completion(.success(try MarkupFile.importing(data)))
        } catch { completion(.failure(error)) }
      }
    } else if provider.canLoadObject(ofClass: NSURL.self) {
      _ = provider.loadObject(ofClass: NSURL.self) { item, error in
        do {
          if let error { throw error }
          guard let url = item as? URL, url.isFileURL else { throw MarkupError.invalidImage }
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          completion(.success(try MarkupFile.importing(Data(contentsOf: url))))
        } catch { completion(.failure(error)) }
      }
    } else {
      completion(.failure(MarkupError.invalidImage))
    }
  }
  static func provider(png: Data) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = "Marked image.png"
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all)
    { completion in
      completion(png, nil)
      return nil
    }
    return provider
  }
}
