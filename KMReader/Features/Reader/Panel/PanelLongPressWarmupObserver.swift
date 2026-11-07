#if os(iOS)
  import UIKit

  /// Observes the existing long press without replacing its delegate or changing arbitration.
  @MainActor
  final class PanelLongPressWarmupObserver: NSObject {
    let onTouchDown: () -> Void
    let onCancel: () -> Void

    private weak var recognizer: UILongPressGestureRecognizer?
    private var startPoint: CGPoint?
    private var cancelled = false

    init(onTouchDown: @escaping () -> Void, onCancel: @escaping () -> Void) {
      self.onTouchDown = onTouchDown
      self.onCancel = onCancel
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
      onCancel()
    }

    @objc private func longPressChanged(_ recognizer: UILongPressGestureRecognizer) {
      switch recognizer.state {
      case .possible:
        guard !cancelled, recognizer.numberOfTouches == 1 else { return }
        if startPoint == nil {
          startPoint = recognizer.location(in: recognizer.view)
          onTouchDown()
        } else if let startPoint,
          hypot(
            recognizer.location(in: recognizer.view).x - startPoint.x,
            recognizer.location(in: recognizer.view).y - startPoint.y
          ) > 10
        {
          cancelled = true
          onCancel()
        }
      case .began:
        cancelled = true
      case .ended, .cancelled, .failed:
        startPoint = nil
        cancelled = false
        onCancel()
      default:
        break
      }
    }
  }
#endif
