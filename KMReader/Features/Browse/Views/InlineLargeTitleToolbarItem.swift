//
// InlineLargeTitleToolbarItem.swift
//
//

import SwiftUI

/// A tab root's inline large bar title: iPhone only, iOS 26+. Renders nothing
/// on other platforms or OS versions, or while gated off (pushed pages).
struct InlineLargeTitleToolbarItem: ToolbarContent {
  let title: String
  let enabled: Bool

  init(title: String, enabled: Bool = true) {
    self.title = title
    self.enabled = enabled
  }

  var body: some ToolbarContent {
    #if os(iOS)
      if enabled && !PlatformHelper.isPad, #available(iOS 26.0, *) {
        ToolbarItem(placement: .largeTitle) {
          InlineLargeBarTitle(title: title)
        }
      }
    #endif
  }
}
