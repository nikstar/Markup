import AppKit

/// DrawingView.swift admits changed samples no more often than every 16 ms.
/// Its UIPanGestureRecognizer supplies a velocity over a gesture interval. The
/// mouse adapter measures over the accepted interval, not a single high-Hz event.
/// Coordinates and velocity are both in image pixels, as in DrawingGesture.swift.
struct TelegramStrokeInput {
  static let minimumInterval: TimeInterval = 0.016
  private var previous: (point: CGPoint, time: TimeInterval)?

  mutating func begin(at point: CGPoint, time: TimeInterval) -> DrawingPoint {
    previous = (point, time)
    return DrawingPoint(location: point, velocity: 0)
  }

  mutating func sample(at point: CGPoint, time: TimeInterval, ending: Bool = false) -> DrawingPoint?
  {
    guard let previous else { return begin(at: point, time: time) }
    let interval = time - previous.time
    guard ending || interval + 0.0000001 >= Self.minimumInterval else { return nil }
    // Duplicate/invalid timestamps must not produce an infinite width impulse.
    let velocity = interval > 0 ? previous.point.distance(to: point) / interval : 0
    self.previous = (point, max(previous.time, time))
    return DrawingPoint(location: point, velocity: min(9_000_000, velocity))
  }
}
