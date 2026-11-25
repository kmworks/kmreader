import Foundation

struct EpubPageLanding {
  let chapterIndex: Int
  let pageIndex: Int
  let layout: EpubPageLayout
  let navigationID: UUID
  var resolvedAnchor: String? = nil
}
