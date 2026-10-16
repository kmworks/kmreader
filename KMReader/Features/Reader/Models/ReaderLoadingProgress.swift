enum ReaderLoadingProgress {
  static let complete = 1.0

  static func displayValue(for progress: Double) -> Double {
    let normalized = min(max(progress, 0), 1)
    guard normalized > 0, normalized < 1 else { return normalized }
    return (normalized * 100).rounded(.down) / 100
  }
}
