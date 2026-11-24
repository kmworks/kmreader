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
  // EPUB-only: returns to the position a footnote/cross-reference link jump
  // started from. Readers without link jumps leave the default no-op.
  let returnFromLink: () -> Void = {}
}
