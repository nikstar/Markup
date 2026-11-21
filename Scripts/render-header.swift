#!/usr/bin/env swift
import AppKit

// Use the same canvas and typefaces as the Scratchpad README. Draw the shipping icon at 2×.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let artwork = root.appendingPathComponent("Documentation/Artwork")
try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
let preview = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
defer { try? FileManager.default.removeItem(at: preview) }
let select = Process()
select.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
select.arguments = ["--print-path"]
let output = Pipe()
select.standardOutput = output
try select.run()
select.waitUntilExit()
let developerDir = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  .trimmingCharacters(in: .whitespacesAndNewlines)
let composer = URL(fileURLWithPath: developerDir).deletingLastPathComponent()
  .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
guard let script = NSFont(name: "SignPainter-HouseScriptSemibold", size: 144),
      let subtitle = NSFont(name: "AvenirNext-Regular", size: 32) else {
  fatalError("The Markup icon, SignPainter and Avenir Next are required.")
}

func color(_ hex: Int) -> NSColor {
  NSColor(srgbRed: CGFloat(hex >> 16) / 255, green: CGFloat(hex >> 8 & 255) / 255,
          blue: CGFloat(hex & 255) / 255, alpha: 1)
}
for (theme, ink, caption) in [("light", 0x993943, 0x544957), ("dark", 0xFFA49B, 0xCEC4D1)] {
  let render = Process()
  render.executableURL = composer
  render.arguments = [root.appendingPathComponent("App/Markup.icon").path, "--export-image",
                      "--output-file", preview.path, "--platform", "macOS", "--design-generation", "27",
                      "--rendition", theme == "dark" ? "Dark" : "Default",
                      "--width", "408", "--height", "408", "--scale", "1"]
  try render.run()
  render.waitUntilExit()
  guard render.terminationStatus == 0, let icon = NSImage(contentsOf: preview) else {
    fatalError("Could not render the Markup icon for the \(theme) header.")
  }
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1700, pixelsHigh: 520,
                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  bitmap.size = NSSize(width: 850, height: 260)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSGraphicsContext.current?.imageInterpolation = .high
  icon.draw(in: NSRect(x: 28, y: 28, width: 204, height: 204))
  ("Markup" as NSString).draw(at: NSPoint(x: 268, y: 98),
                              withAttributes: [.font: script, .foregroundColor: color(ink)])
  ("Screenshot editor for macOS" as NSString).draw(at: NSPoint(x: 275, y: 45),
                              withAttributes: [.font: subtitle, .foregroundColor: color(caption)])
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!
    .write(to: artwork.appendingPathComponent("header-\(theme).png"), options: .atomic)
}
