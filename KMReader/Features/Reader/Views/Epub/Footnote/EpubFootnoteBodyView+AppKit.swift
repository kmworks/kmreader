#if os(macOS)
  import SwiftUI
  import WebKit

  extension EpubFootnoteBodyView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
      Coordinator(onContentHeightChange: onContentHeightChange, onOpenLink: onOpenLink)
    }

    func makeNSView(context: Context) -> WKWebView {
      let configuration = WKWebViewConfiguration()
      configuration.userContentController.add(
        WeakWKScriptMessageHandler(delegate: context.coordinator),
        name: Self.messageHandlerName
      )
      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.navigationDelegate = context.coordinator
      webView.underPageBackgroundColor = .clear
      webView.allowsMagnification = false
      context.coordinator.load(makeHTML(), in: webView)
      return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
      context.coordinator.update(onContentHeightChange: onContentHeightChange, onOpenLink: onOpenLink)
      context.coordinator.load(makeHTML(), in: webView)
    }
  }
#endif
