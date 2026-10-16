import Foundation

@MainActor
protocol NativePagedPagePresentationHost: AnyObject {
  func hasVisiblePagePresentationContent() -> Bool
  func applyPagePresentationInvalidation(_ invalidation: ReaderPagePresentationInvalidation)
}
