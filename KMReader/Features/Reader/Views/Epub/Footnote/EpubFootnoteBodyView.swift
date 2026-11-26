#if os(iOS) || os(macOS)
  import SwiftUI
  import WebKit

  /// Renders the sanitised note body inside the footnote popup.
  struct EpubFootnoteBodyView {
    static let messageHandlerName = "footnoteBridge"

    let footnote: EpubFootnote
    let theme: ReaderTheme
    let onContentHeightChange: (CGFloat) -> Void
    let onOpenLink: (URL) -> Void

    func makeHTML() -> String {
      EpubFootnoteDocument.html(
        footnote: footnote,
        theme: theme,
        scriptMessageHandler: Self.messageHandlerName
      )
    }
  }

  extension EpubFootnoteBodyView {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
      private(set) var loadedHTML: String?
      private var onContentHeightChange: (CGFloat) -> Void
      private var onOpenLink: (URL) -> Void

      init(onContentHeightChange: @escaping (CGFloat) -> Void, onOpenLink: @escaping (URL) -> Void) {
        self.onContentHeightChange = onContentHeightChange
        self.onOpenLink = onOpenLink
      }

      func update(
        onContentHeightChange: @escaping (CGFloat) -> Void,
        onOpenLink: @escaping (URL) -> Void
      ) {
        self.onContentHeightChange = onContentHeightChange
        self.onOpenLink = onOpenLink
      }

      func load(_ html: String, in webView: WKWebView) {
        guard loadedHTML != html else { return }
        loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
      }

      func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
      ) {
        guard message.name == EpubFootnoteBodyView.messageHandlerName,
          let body = message.body as? [String: Any],
          (body["type"] as? String) == "height",
          let height = body["height"] as? Double,
          height > 0
        else {
          return
        }
        onContentHeightChange(CGFloat(height))
      }

      func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
      ) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
          decisionHandler(.allow, preferences)
          return
        }
        decisionHandler(.cancel, preferences)
        if url.scheme == EpubResourceScheme.scheme {
          onOpenLink(url)
        }
      }
    }
  }
#endif
