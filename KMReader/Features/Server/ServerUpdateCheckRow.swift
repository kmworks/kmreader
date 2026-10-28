//
// ServerUpdateCheckRow.swift
//

import SwiftUI

struct ServerUpdateCheckRow: View {
  let check: ServerUpdateCheck

  var body: some View {
    if let update = check.update {
      if let url = update.releaseURL {
        Link(destination: url) {
          label(
            title: String(localized: "Update Available"),
            value: update.version,
            icon: "arrow.down.circle"
          )
          .contentShape(Rectangle())
        }
      } else {
        label(
          title: String(localized: "Update Available"),
          value: update.version,
          icon: "arrow.down.circle"
        )
      }
    } else if !check.enabled {
      label(
        title: String(localized: "Update Checks"),
        value: String(localized: "Disabled"),
        icon: "checkmark.circle"
      )
    } else if check.checkedAt == nil {
      label(
        title: String(localized: "Update Checks"),
        value: String(localized: "Not checked yet"),
        icon: "clock"
      )
    } else {
      label(
        title: String(localized: "Server Version"),
        value: String(localized: "Up to date"),
        icon: "checkmark.circle"
      )
    }
    if let checkedAt = check.checkedAt {
      LabeledContent {
        Text(checkedAt.formatted(.relative(presentation: .named)))
      } label: {
        Label(String(localized: "Last Checked"), systemImage: "calendar")
      }
    }
  }

  private func label(title: String, value: String, icon: String) -> some View {
    LabeledContent {
      Text(value)
    } label: {
      Label(title, systemImage: icon)
    }
  }
}
