import Foundation

nonisolated enum EpubRenderingEngine: String, CaseIterable, Identifiable, Sendable {
  case webView = "webView"
  case coreText = "coreText"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .webView:
      return "WebView"
    case .coreText:
      return "Core Text"
    }
  }
}
