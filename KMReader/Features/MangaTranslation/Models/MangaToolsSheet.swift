//
// MangaToolsSheet.swift
//
//

import Foundation

/// A management sheet opened from the manga tools settings.
enum MangaToolsSheet: Identifiable, Hashable {
  case providers
  case model(MangaModelRole)
  #if os(iOS)
    case panelModel
  #endif

  var id: String {
    switch self {
    case .providers: return "providers"
    case .model(let role): return "model.\(role.rawValue)"
    #if os(iOS)
      case .panelModel: return "panelModel"
    #endif
    }
  }
}
