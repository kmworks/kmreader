#if os(iOS)
  @MainActor
  enum EpubPageTargetResolver {
    static func next(
      chapterIndex: Int,
      subPageIndex: Int,
      viewModel: EpubReaderViewModel
    ) -> EpubPageTarget? {
      let storedCount = viewModel.chapterPageCount(at: chapterIndex) ?? 1
      if subPageIndex < storedCount - 1 {
        return EpubPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex + 1, preferLastPage: false)
      }
      let nextChapter = chapterIndex + 1
      if nextChapter < viewModel.chapterCount {
        return EpubPageTarget(chapterIndex: nextChapter, subPageIndex: 0, preferLastPage: false)
      }
      return nil
    }

    static func previous(
      chapterIndex: Int,
      subPageIndex: Int,
      viewModel: EpubReaderViewModel
    ) -> EpubPageTarget? {
      if subPageIndex > 0 {
        return EpubPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex - 1, preferLastPage: false)
      }
      let previousChapter = chapterIndex - 1
      guard previousChapter >= 0 else { return nil }
      let previousCount = viewModel.chapterPageCount(at: previousChapter) ?? 1
      return EpubPageTarget(
        chapterIndex: previousChapter,
        subPageIndex: max(0, previousCount - 1),
        preferLastPage: previousCount <= 1
      )
    }
  }
#endif
