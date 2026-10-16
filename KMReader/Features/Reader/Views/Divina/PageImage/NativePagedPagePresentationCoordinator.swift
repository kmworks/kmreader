import Foundation

@MainActor
final class NativePagedPagePresentationCoordinator {
  weak var host: (any NativePagedPagePresentationHost)?

  private weak var observedViewModel: ReaderViewModel?
  private var pagePresentationObserverToken: UUID?
  private var pendingInvalidation: ReaderPagePresentationInvalidation?

  func update(viewModel: ReaderViewModel) {
    guard observedViewModel !== viewModel || pagePresentationObserverToken == nil else { return }
    unregister()

    observedViewModel = viewModel
    pagePresentationObserverToken = viewModel.addPagePresentationInvalidationObserver { [weak self] invalidation in
      guard let self else { return }
      if let pendingInvalidation {
        self.pendingInvalidation = pendingInvalidation.merged(with: invalidation)
      } else {
        self.pendingInvalidation = invalidation
      }
      flushIfPossible()
    }
  }

  func flushIfPossible() {
    guard let pendingInvalidation else { return }
    guard let host else { return }
    guard host.hasVisiblePagePresentationContent() else { return }
    self.pendingInvalidation = nil
    host.applyPagePresentationInvalidation(pendingInvalidation)
  }

  func teardown() {
    unregister()
    pendingInvalidation = nil
    host = nil
  }

  private func unregister() {
    guard let observedViewModel, let pagePresentationObserverToken else {
      self.observedViewModel = nil
      self.pagePresentationObserverToken = nil
      return
    }

    observedViewModel.removePagePresentationInvalidationObserver(pagePresentationObserverToken)
    self.observedViewModel = nil
    self.pagePresentationObserverToken = nil
  }
}
