//
// TrackerAccountRow.swift
//

import SwiftUI

struct TrackerAccountRow: View {
  let provider: TrackerProvider
  let account: TrackerAccount?
  let isPending: Bool
  let webURL: URL?
  let onLogout: () -> Void

  var body: some View {
    HStack {
      Text(provider.displayName)
      Spacer()
      if isPending {
        ProgressView()
      } else if account?.loggedIn == true {
        Text(account?.username ?? String(localized: "Connected"))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Button(String(localized: "Disconnect"), role: .destructive, action: onLogout)
          .font(.caption)
      } else if let webURL {
        Link(String(localized: "Connect on Web"), destination: webURL)
          .font(.caption)
      }
    }
  }
}
