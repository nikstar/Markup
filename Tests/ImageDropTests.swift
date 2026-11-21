import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Markup

private final class TestPromise: NSObject, NSFilePromiseProviderDelegate {
  func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType type: String) -> String { "Screenshot.png" }
  func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                           completionHandler: @escaping (Error?) -> Void) {
    XCTFail("Checking the hover operation must not request a file")
    completionHandler(CocoaError(.userCancelled))
  }
}

// AppKit allows calling an actual NSFilePromiseReceiver only during a system
// drag. Deliver on its supplied queue here without commandeering the user's mouse.
private final class DeliveredPromise: NSFilePromiseReceiver {
  var contents = Data()
  var name = ""
  var failure: Error?
  var requestedDirectory: URL?
  override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:],
                                     operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
    requestedDirectory = destinationDir
    operationQueue.addOperation { [self] in
      let url = destinationDir.appendingPathComponent(name)
      do {
        if let failure { throw failure }
        try contents.write(to: url)
        reader(url, nil)
      } catch { reader(url, error) }
    }
  }
}

@MainActor
private final class Drag: NSObject, NSDraggingInfo {
  let draggingPasteboard = NSPasteboard.withUniqueName()
  var draggingSourceOperationMask: NSDragOperation = .copy
  var draggingDestinationWindow: NSWindow?
  var draggingLocation = NSPoint.zero
  var draggedImageLocation = NSPoint.zero
  nonisolated var draggedImage: NSImage? { nil }
  var draggingSource: Any? { nil }
  var draggingSequenceNumber: Int { 1 }
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 0
  var springLoadingHighlight: NSSpringLoadingHighlight = .none
  func resetSpringLoading() {}
  func slideDraggedImage(to screenPoint: NSPoint) {}
  nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
  func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
                              classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                              using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@MainActor
final class ImageDropTests: XCTestCase {
  func testScreenshotHitRegionAndPanelOnOffsetDisplays() throws {
    for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900),
                   CGRect(x: -1920, y: 240, width: 1920, height: 1080),
                   CGRect(x: 120, y: -1080, width: 1920, height: 1080)] {
      for right in [true, false] {
        for size in [CGSize(width: 210, height: 118), CGSize(width: 38, height: 146),
                     CGSize(width: 211, height: 12), CGSize(width: 12, height: 146)] {
          let rect = CGRect(x: right ? screen.maxX - size.width - 13 : screen.minX + 13,
                            y: screen.minY + 13, width: size.width, height: size.height)
          let hit = try XCTUnwrap(ScreenshotThumbnail.locate(in: screen, window: 3, hit: rect.contains))
          XCTAssertEqual(hit.panelFrame.minY, rect.maxY + 8, accuracy: 2)
          XCTAssertEqual(right ? hit.panelFrame.maxX : hit.panelFrame.minX,
                         right ? rect.maxX : rect.minX, accuracy: 2)
          XCTAssertEqual(hit.panelFrame.width, rect.width, accuracy: 2)
          XCTAssertEqual(hit.panelFrame.height, rect.height * 2 / 3, accuracy: 2)
          XCTAssertTrue(screen.contains(hit.panelFrame))
        }
      }
      XCTAssertNil(ScreenshotThumbnail.locate(in: screen, window: 2, hit: screen.contains))
      XCTAssertNil(ScreenshotThumbnail.locate(in: screen, window: 2) { _ in false })
      let toolbar = CGRect(x: screen.midX - 250, y: screen.minY + 16, width: 500, height: 54)
      XCTAssertNil(ScreenshotThumbnail.locate(in: screen, window: 2, hit: toolbar.contains))
    }
  }

  func testStatusWindowRoutesDropsAndKeepsItsMenu() throws {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    defer { NSStatusBar.system.removeStatusItem(status) }
    let menu = NSMenu()
    status.menu = menu
    var files = [URL](), images = [Data]()
    let handler = ImageDrop(file: { files.append($0) }, image: { data, _ in images.append(data) })
    let target = try XCTUnwrap(ImageDropTarget.install(on: status, drop: handler))
    let window = try XCTUnwrap(status.button?.window)
    XCTAssertTrue(status.menu === menu)
    XCTAssertTrue(window.delegate === target)
    let drag = Drag()
    defer { drag.draggingPasteboard.releaseGlobally() }
    drag.draggingDestinationWindow = window
    let directory = try DropDirectory()
    let url = directory.url.appendingPathComponent("Test.png")
    let pixels = try SampleImage.file().source
    try pixels.write(to: url)
    let raw = NSPasteboardItem()
    raw.setData(pixels, forType: .png)
    drag.draggingPasteboard.writeObjects([url as NSURL, raw])
    drag.draggingSourceOperationMask = .move
    XCTAssertEqual(target.draggingEntered(drag), [])
    drag.draggingSourceOperationMask = .copy
    XCTAssertEqual(target.draggingEntered(drag), .copy)
    XCTAssertTrue(target.performDragOperation(drag))
    XCTAssertEqual(files, [url])
    XCTAssertEqual(images, [pixels])
    XCTAssertTrue(status.menu === menu)
  }

  func testScreenshotPromiseRecognizedBeforeItIsFulfilled() throws {
    let delegate = TestPromise()
    let drag = Drag()
    defer { drag.draggingPasteboard.releaseGlobally() }
    let panel = ScreenshotDropPanel(drop: ImageDrop(file: { _ in XCTFail() }, image: { _, _ in XCTFail() }))
    XCTAssertFalse(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    let glass = try XCTUnwrap(panel.contentView as? NSGlassEffectView)
    let target = panel.target
    for (type, expected) in [(UTType.png, NSDragOperation.copy), (.plainText, [])] {
      drag.draggingPasteboard.clearContents()
      drag.draggingPasteboard.writeObjects([NSFilePromiseProvider(fileType: type.identifier, delegate: delegate)])
      XCTAssertEqual(target.draggingEntered(drag), expected)
      XCTAssertEqual(glass.tintColor != nil, !expected.isEmpty)
      target.draggingExited(drag)
      XCTAssertNil(glass.tintColor)
    }
  }

  func testMultiplePromisesDeliverAndReportCancellationIndependently() throws {
    let ok = DeliveredPromise(), cancelled = DeliveredPromise()
    ok.contents = try SampleImage.file().source
    ok.name = "Screenshot.png"
    cancelled.failure = CocoaError(.userCancelled)
    let delivered = expectation(description: "Two independent deliveries")
    delivered.expectedFulfillmentCount = 2
    let drop = ImageDrop(file: { _ in XCTFail() }, image: { bytes, name in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual(bytes, ok.contents)
      XCTAssertEqual(name, "Screenshot")
      delivered.fulfill()
    }, failed: { error in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual((error as NSError).code, CocoaError.userCancelled.rawValue)
      delivered.fulfill()
    })
    try drop.receive([ok, cancelled])
    XCTAssertNotNil(ok.requestedDirectory)
    XCTAssertEqual(ok.requestedDirectory, cancelled.requestedDirectory)
    wait(for: [delivered], timeout: 3)
  }

  func testCoordinatedPromiseBytesAndNameSurviveCleanup() throws {
    let png = try SampleImage.file().source
    var received: (Data, String)?
    var stageURL: URL?
    try autoreleasepool {
      let directory = try DropDirectory()
      stageURL = directory.url
      let output = directory.url.appendingPathComponent("Screenshot of a window.png")
      try png.write(to: output)
      received = try directory.read(output)
      XCTAssertThrowsError(try directory.read(directory.url.deletingLastPathComponent()))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(stageURL).path))
    XCTAssertEqual(received?.0, png)
    XCTAssertEqual(received?.1, "Screenshot of a window")
  }
}
