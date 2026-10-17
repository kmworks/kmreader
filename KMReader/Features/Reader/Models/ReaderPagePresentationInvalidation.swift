import Foundation

enum ReaderPagePresentationInvalidation: Equatable {
  case all
  case pages(Set<ReaderPageID>)
  /// Translation-session state changed (queue, phases, results, overrides);
  /// hosts re-render visible pages so overlays and per-page buttons catch up.
  case mangaTranslation

  func merged(with other: ReaderPagePresentationInvalidation) -> ReaderPagePresentationInvalidation {
    switch (self, other) {
    case (.pages(let lhs), .pages(let rhs)):
      return .pages(lhs.union(rhs))
    case (.mangaTranslation, .mangaTranslation):
      return .mangaTranslation
    default:
      return .all
    }
  }
}
