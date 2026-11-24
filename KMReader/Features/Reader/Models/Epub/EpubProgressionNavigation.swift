#if os(iOS) || os(macOS)
  struct EpubProgressionNavigation {
    let chapterIndex: Int
    let progression: Double
    let restoresRemoteProgress: Bool

    func pageIndex(pageCount: Int) -> Int {
      max(0, min(pageCount - 1, Int((Double(pageCount) * progression).rounded(.down))))
    }
  }
#endif
