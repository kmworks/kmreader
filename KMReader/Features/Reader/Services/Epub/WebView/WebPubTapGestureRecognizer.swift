#if os(iOS)
  import UIKit
  import WebKit

  final class WebPubTapGestureRecognizer: UITapGestureRecognizer {
    private var linkHitTest: WebPubLinkHitTest?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      linkHitTest = nil
      if let touch = touches.first {
        var touchedView = touch.view
        while let candidate = touchedView {
          if let webView = candidate as? WKWebView {
            linkHitTest = WebPubLinkHitTest(webView: webView, point: touch.location(in: webView))
            break
          }
          touchedView = candidate.superview
        }
      }
      super.touchesBegan(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      linkHitTest = nil
      super.touchesCancelled(touches, with: event)
    }

    func performIfNotLink(_ action: @escaping () -> Void) {
      guard state == .ended else { return }
      if let linkHitTest {
        linkHitTest.performIfNotLink(action)
      } else {
        action()
      }
    }
  }
#endif
