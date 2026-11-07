#if os(iOS)
  import UIKit

  /// Observes the existing long press without replacing its delegate or changing arbitration.
  @MainActor
  final class PanelLongPressWarmupObserver: NSObject {
    private let controller: PanelModeController
    private let currentPage: () -> (bookId: String, page: BookPage, presentation: PanelPagePresentation)?

    private weak var recognizer: UILongPressGestureRecognizer?
    private var startPoint: CGPoint?
    private var cancelled = false

    init(
      controller: PanelModeController,
      currentPage: @escaping () -> (bookId: String, page: BookPage, presentation: PanelPagePresentation)?
    ) {
      self.controller = controller
      self.currentPage = currentPage
      super.init()
    }

    func attach(to recognizer: UILongPressGestureRecognizer) {
      self.recognizer = recognizer
      recognizer.addTarget(self, action: #selector(longPressChanged(_:)))
    }

    func detach() {
      recognizer?.removeTarget(self, action: #selector(longPressChanged(_:)))
      recognizer = nil
      startPoint = nil
      cancelled = false
      controller.cancelEngagementPreparation()
    }

    @objc private func longPressChanged(_ recognizer: UILongPressGestureRecognizer) {
      switch recognizer.state {
      case .possible:
        guard !cancelled, recognizer.numberOfTouches == 1 else { return }
        if startPoint == nil {
          startPoint = recognizer.location(in: recognizer.view)
          if let currentPage = currentPage() {
            controller.prepareForPossibleEngagement(
              bookId: currentPage.bookId,
              page: currentPage.page,
              presentation: currentPage.presentation
            )
          }
        } else if let startPoint,
          hypot(
            recognizer.location(in: recognizer.view).x - startPoint.x,
            recognizer.location(in: recognizer.view).y - startPoint.y
          ) > 10
        {
          cancelled = true
          controller.cancelEngagementPreparation()
        }
      case .began:
        cancelled = true
      case .ended, .cancelled, .failed:
        startPoint = nil
        cancelled = false
        controller.cancelEngagementPreparation()
      default:
        break
      }
    }
  }
#endif
