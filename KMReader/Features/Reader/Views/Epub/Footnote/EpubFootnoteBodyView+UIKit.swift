#if os(iOS)
  import SwiftUI
  import WebKit

  extension EpubFootnoteBodyView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
      Coordinator(onContentHeightChange: onContentHeightChange, onOpenLink: onOpenLink)
    }

    func makeUIView(context: Context) -> WKWebView {
      let configuration = WKWebViewConfiguration()
      configuration.userContentController.add(
        WeakWKScriptMessageHandler(delegate: context.coordinator),
        name: Self.messageHandlerName
      )
      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.navigationDelegate = context.coordinator
      webView.isOpaque = false
      webView.backgroundColor = .clear
      webView.scrollView.backgroundColor = .clear
      webView.scrollView.contentInsetAdjustmentBehavior = .never
      webView.scrollView.showsHorizontalScrollIndicator = false
      context.coordinator.load(makeHTML(), in: webView)
      return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
      context.coordinator.update(onContentHeightChange: onContentHeightChange, onOpenLink: onOpenLink)
      context.coordinator.load(makeHTML(), in: webView)
    }
  }
#endif
