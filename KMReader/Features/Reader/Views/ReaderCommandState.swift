import Foundation

struct ReaderCommandState: Equatable {
  var isActive: Bool = false
  var supportsReaderSettings: Bool = false
  var supportsBookDetails: Bool = false
  var hasPages: Bool = false
  var hasTableOfContents: Bool = false
  var supportsPageJump: Bool = false
  var supportsBookNavigation: Bool = false
  var canOpenPreviousBook: Bool = false
  var canOpenNextBook: Bool = false
  var readingDirection: ReadingDirection = .ltr
  var availableReadingDirections: [ReadingDirection] = ReadingDirection.availableCases
  var pageLayout: PageLayout = .auto
  var soloCoverPage: Bool = true
  var pageSoloActions: [ReaderPageSoloActions.Action] = []
  var commandPageIDs: [ReaderPageID] = []
  var displayPageNumbersByID: [ReaderPageID: Int] = [:]
  var rotation: ReaderRotation = .none
  var splitWidePageMode: SplitWidePageMode = .none
  var continuousScroll: Bool = false
  var supportsSearch: Bool = false
  var canSearch: Bool = false
  var supportsReadingDirectionSelection: Bool = false
  var supportsPageLayoutSelection: Bool = false
  var supportsRotationSelection: Bool = false
  var supportsDualPageOptions: Bool = false
  var supportsSplitWidePageMode: Bool = false
  var supportsContinuousScrollToggle: Bool = false
}
