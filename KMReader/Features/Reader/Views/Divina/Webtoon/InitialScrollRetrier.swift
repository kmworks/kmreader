import Foundation

struct InitialScrollRetrier {
  typealias DelayScheduler = @MainActor (TimeInterval, @escaping () -> Void) -> Void

  private(set) var attempts: Int = 0
  let maxRetries: Int

  mutating func reset() {
    attempts = 0
  }

  @MainActor
  mutating func schedule(
    after delay: TimeInterval,
    using scheduler: DelayScheduler,
    action: @escaping () -> Void
  ) {
    guard attempts < maxRetries else { return }
    attempts += 1
    scheduler(delay, action)
  }
}
