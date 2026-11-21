import AppKit
import CryptoKit

/// History stores the original image once. Each undo entry saves only the changed
/// range of annotations and the crop, including the old values needed for undo.
struct ImageEditHistory: Codable {
  struct Edit: Codable {
    let name: String
    let start: Int
    let removed: [Annotation]
    let inserted: [Annotation]
    let oldCrop: CGRect?
    let newCrop: CGRect?

    init(from old: MarkupFile, to new: MarkupFile, name: String) {
      self.name = name
      let a = old.annotations, b = new.annotations
      var prefix = 0, suffix = 0
      while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
      while suffix < min(a.count, b.count) - prefix,
            a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
      start = prefix
      removed = Array(a[prefix..<(a.count - suffix)])
      inserted = Array(b[prefix..<(b.count - suffix)])
      oldCrop = old.crop
      newCrop = new.crop
    }

    func applying(to file: MarkupFile, backward: Bool) throws -> MarkupFile {
      let remove = backward ? inserted : removed
      let insert = backward ? removed : inserted
      guard start >= 0, start <= file.annotations.count,
            remove.count <= file.annotations.count - start,
            file.crop == (backward ? newCrop : oldCrop) else { throw MarkupError.invalidDocument }
      let range = start..<(start + remove.count)
      guard file.annotations[range].elementsEqual(remove) else { throw MarkupError.invalidDocument }
      var next = file
      next.annotations.replaceSubrange(range, with: insert)
      next.crop = backward ? oldCrop : newCrop
      return next
    }
  }

  private(set) var edits: [Edit] = []
  var cursor = 0
  mutating func append(from old: MarkupFile, to new: MarkupFile, name: String, limit: Int) {
    edits.removeSubrange(cursor...)
    edits.append(Edit(from: old, to: new, name: name))
    if edits.count > limit { edits.removeFirst(edits.count - limit) }
    cursor = edits.count
  }

  /// Rebuild both native UndoManager stacks, including redo after closing on an undo.
  func restore(_ file: MarkupFile, in session: EditorSession) throws {
    guard (0...edits.count).contains(cursor), edits.count <= session.undo.levelsOfUndo else {
      throw MarkupError.invalidDocument
    }
    var base = file
    for edit in edits.prefix(cursor).reversed() { base = try edit.applying(to: base, backward: true) }
    var current = base
    let states = try edits.map { edit in
      current = try edit.applying(to: current, backward: false)
      return current
    }
    session.undo.removeAllActions()
    session.file = base
    for (edit, state) in zip(edits, states) { session.commit(state, name: edit.name) }
    for _ in cursor..<edits.count { session.undo.undo() }
  }
}

struct ImageEditArchive: Codable {
  var version = 1
  let file: MarkupFile
  let history: ImageEditHistory

  private static let attribute = "dev.nikstar.Markup.history"
  static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  static func bucket(for url: URL) -> String {
    digest(Data(url.resolvingSymlinksInPath().standardizedFileURL.path.utf8))
  }
  private static var root: URL {
    URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "dev.nikstar.Markup")
      .appending(path: "Image History", directoryHint: .isDirectory)
  }
  private static func url(bucket: String, digest: String) -> URL {
    root.appending(path: bucket, directoryHint: .isDirectory).appending(path: digest)
  }

  static func load(image url: URL, digest: String) -> Self? {
    var bytes = [UInt8](repeating: 0, count: 64)
    let count = getxattr(url.path, attribute, &bytes, bytes.count, 0, 0)
    let local = bucket(for: url)
    var buckets = [local]
    if count == bytes.count, bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
      let origin = String(decoding: bytes, as: UTF8.self)
      if origin != local { buckets.append(origin) }
    }
    for key in buckets {
      guard let data = try? Data(contentsOf: Self.url(bucket: key, digest: digest)),
            let archive = try? PropertyListDecoder().decode(Self.self, from: data),
            archive.version == 1 else { continue }
      return archive
    }
    return nil
  }

  func stage(bucket: String, digest: String) throws -> URL {
    let record = Self.url(bucket: bucket, digest: digest)
    try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true,
                                           attributes: [.posixPermissions: 0o700])
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    try encoder.encode(self).write(to: record, options: .atomic)
    return record
  }

  static func discard(for image: URL) throws {
    // A moved or copied image can point to another path’s archive. Detach this
    // image from that archive and prune only the history owned by its current path.
    let directory = root.appending(path: bucket(for: image), directoryHint: .isDirectory)
    do { try FileManager.default.removeItem(at: directory) }
    catch let error as CocoaError where error.code == .fileNoSuchFile {}
    if removexattr(image.path, attribute, 0) != 0 && errno != ENOATTR && errno != ENOTSUP {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  static func didSave(_ record: URL, bucket: String, image: URL) {
    // Only an opaque local lookup key travels with the image. Volumes without
    // extended attributes still restore history by path and exact image digest.
    _ = bucket.utf8CString.withUnsafeBytes { setxattr(image.path, attribute, $0.baseAddress, 64, 0, 0) }
    if let records = try? FileManager.default.contentsOfDirectory(at: record.deletingLastPathComponent(),
                                                                 includingPropertiesForKeys: nil) {
      for old in records where old != record && old.lastPathComponent.count == 64 {
        try? FileManager.default.removeItem(at: old)
      }
    }
  }
}
