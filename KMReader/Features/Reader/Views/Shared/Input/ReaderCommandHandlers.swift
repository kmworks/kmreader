import Foundation

typealias ReaderTapZoneTapHandler = (_ normalizedX: CGFloat, _ normalizedY: CGFloat) -> Void

struct ReaderCommandHandlers {
  let showReaderSettings: () -> Void
  let showBookDetails: () -> Void
  let showTableOfContents: () -> Void
  let showPageJump: () -> Void
  let showSearch: () -> Void
  let showBookNavigation: () -> Void
  let setReadingDirection: (ReadingDirection) -> Void
  let setPageLayout: (PageLayout) -> Void
  let toggleSoloCoverPage: () -> Void
  let toggleSoloPage: (ReaderPageID) -> Void
  let sharePage: (ReaderPageID) -> Void
  let setRotation: (ReaderRotation) -> Void
  let setSplitWidePageMode: (SplitWidePageMode) -> Void
  let toggleContinuousScroll: () -> Void
  let toggleMangaTranslation: () -> Void
  let showMangaTranslationSettings: () -> Void
  // EPUB-only: returns to the position before an explicit jump (scrub, TOC,
  // bookmark, or in-book link). Readers without jumps leave the default no-op.
  let returnToPreviousPosition: () -> Void
  let toggleBookmark: () -> Void

  init(
    showReaderSettings: @escaping () -> Void,
    showBookDetails: @escaping () -> Void,
    showTableOfContents: @escaping () -> Void,
    showPageJump: @escaping () -> Void,
    showSearch: @escaping () -> Void,
    showBookNavigation: @escaping () -> Void,
    setReadingDirection: @escaping (ReadingDirection) -> Void,
    setPageLayout: @escaping (PageLayout) -> Void,
    toggleSoloCoverPage: @escaping () -> Void,
    toggleSoloPage: @escaping (ReaderPageID) -> Void,
    sharePage: @escaping (ReaderPageID) -> Void,
    setRotation: @escaping (ReaderRotation) -> Void,
    setSplitWidePageMode: @escaping (SplitWidePageMode) -> Void,
    toggleContinuousScroll: @escaping () -> Void,
    toggleMangaTranslation: @escaping () -> Void,
    showMangaTranslationSettings: @escaping () -> Void,
    returnToPreviousPosition: @escaping () -> Void = {},
    toggleBookmark: @escaping () -> Void = {}
  ) {
    self.showReaderSettings = showReaderSettings
    self.showBookDetails = showBookDetails
    self.showTableOfContents = showTableOfContents
    self.showPageJump = showPageJump
    self.showSearch = showSearch
    self.showBookNavigation = showBookNavigation
    self.setReadingDirection = setReadingDirection
    self.setPageLayout = setPageLayout
    self.toggleSoloCoverPage = toggleSoloCoverPage
    self.toggleSoloPage = toggleSoloPage
    self.sharePage = sharePage
    self.setRotation = setRotation
    self.setSplitWidePageMode = setSplitWidePageMode
    self.toggleContinuousScroll = toggleContinuousScroll
    self.toggleMangaTranslation = toggleMangaTranslation
    self.showMangaTranslationSettings = showMangaTranslationSettings
    self.returnToPreviousPosition = returnToPreviousPosition
    self.toggleBookmark = toggleBookmark
  }
}
