#if os(iOS)
  import WebKit

  @MainActor
  final class WebPubLinkHitTest {
    private var isLink: Bool?
    private var action: (() -> Void)?

    init(webView: WKWebView, point: CGPoint) {
      let url = webView.url
      let window = webView.window
      // Submit at touch-down, before WebKit can activate the link and change
      // the document or scroll position. Each gesture owns its own response.
      webView.callAsyncJavaScript(
        """
        const viewport = window.visualViewport;
        const clientX = viewport ? viewport.offsetLeft + x * viewport.width / width : x;
        const clientY = viewport ? viewport.offsetTop + y * viewport.height / height : y;
        const element = document.elementFromPoint(clientX, clientY);
        const link = element && element.closest('a');
        return !!(link && (link.hasAttribute('href') || link.hasAttribute('xlink:href')));
        """,
        arguments: ["x": point.x, "y": point.y, "width": webView.bounds.width, "height": webView.bounds.height],
        in: nil,
        in: .page
      ) { [weak self, weak webView, weak window] result in
        guard let self else { return }
        guard let webView, let window, webView.window === window, webView.url == url else {
          self.invalidate()
          return
        }
        switch result {
        case .success(let value):
          self.isLink = value as? Bool ?? true
          self.completeIfReady()
        case .failure(let error):
          AppLogger(.reader).error("EPUB link hit test failed: \(error.localizedDescription)")
          self.invalidate()
        }
      }
    }

    func performIfNotLink(_ action: @escaping () -> Void) {
      self.action = action
      completeIfReady()
    }

    private func invalidate() {
      isLink = true
      action = nil
    }

    private func completeIfReady() {
      guard let isLink else { return }
      let pendingAction = action
      action = nil
      if !isLink { pendingAction?() }
    }
  }
#endif
