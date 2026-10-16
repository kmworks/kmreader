import Foundation

@MainActor
func scheduleOnMain(after delay: TimeInterval, action: @escaping () -> Void) {
  Task { @MainActor in
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    action()
  }
}
