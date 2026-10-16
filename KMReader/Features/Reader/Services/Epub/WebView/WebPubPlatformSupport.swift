#if os(iOS) || os(macOS)
  #if os(iOS)
    import UIKit
  #elseif os(macOS)
    import AppKit
  #endif

  import Foundation
  import WebKit

  #if os(iOS)
    extension ReaderTheme {
      var uiColorBackground: UIColor { UIColor(hex: backgroundColorHex) ?? .white }
      var uiColorText: UIColor { UIColor(hex: textColorHex) ?? .black }
    }
  #endif

  final class WeakWKScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
      self.delegate = delegate
      super.init()
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      delegate?.userContentController(userContentController, didReceive: message)
    }
  }

  enum WebPubJavaScriptSupport {
    static func encodeJSON(_ object: Any, fallback: String) -> String {
      guard
        let data = try? JSONSerialization.data(withJSONObject: object, options: []),
        let json = String(data: data, encoding: .utf8)
      else {
        return fallback
      }
      return json
    }

    static func escapedJSONString(_ value: String?) -> String {
      guard let value else { return "null" }
      var escaped = value
      escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
      escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
      escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
      escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
      escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
      return "\"\(escaped)\""
    }
  }

  extension WKWebViewConfiguration {
    func registerEpubResourceSchemeHandler(_ handler: EpubResourceSchemeHandler) {
      setURLSchemeHandler(handler, forURLScheme: EpubResourceScheme.scheme)
    }
  }

  extension WKWebView {
    func loadEPUBDocument(
      url: URL,
      rootURL: URL
    ) {
      guard let schemeURL = EpubResourceScheme.url(for: url, rootURL: rootURL) else { return }
      load(URLRequest(url: schemeURL))
    }
  }

  extension URL {
    var deletingFragment: URL {
      guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
        return self
      }
      components.fragment = nil
      return components.url ?? self
    }
  }
#endif
