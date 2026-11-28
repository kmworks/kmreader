//
// PageTransitionStyle.swift
//
//

import Foundation

enum PageTransitionStyle: String, CaseIterable, Hashable, Sendable {
  case scroll = "scroll"
  case cover = "cover"
  case fade = "fade"
  case pageCurl = "pageCurl"

  /// Platform-specific available cases
  static var availableCases: [PageTransitionStyle] {
    #if os(iOS)
      return [.scroll, .cover, .fade, .pageCurl]
    #else
      return [.scroll, .cover, .fade]
    #endif
  }

  static var epubAvailableCases: [PageTransitionStyle] {
    #if os(iOS)
      return [.scroll, .cover, .pageCurl]
    #else
      return [.scroll, .cover]
    #endif
  }

  var displayName: String {
    switch self {
    case .scroll: return String(localized: "reader.page_transition.scroll")
    case .cover: return String(localized: "reader.page_transition.cover")
    case .fade: return String(localized: "reader.page_transition.fade")
    case .pageCurl: return String(localized: "reader.page_transition.page_curl")
    }
  }

  var description: String {
    switch self {
    case .scroll: return String(localized: "reader.page_transition.scroll.description")
    case .cover: return String(localized: "reader.page_transition.cover.description")
    case .fade: return String(localized: "reader.page_transition.fade.description")
    case .pageCurl: return String(localized: "reader.page_transition.page_curl.description")
    }
  }
}
