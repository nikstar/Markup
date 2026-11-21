import Foundation

struct MarkupPreferences {
  let defaults: UserDefaults
  init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

  var keepsEditHistory: Bool {
    get { defaults.object(forKey: "KeepEditHistory") as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: "KeepEditHistory") }
  }

  var reversesScrollPan: Bool {
    get { defaults.bool(forKey: "ReverseScrollPan") }
    nonmutating set { defaults.set(newValue, forKey: "ReverseScrollPan") }
  }
}
