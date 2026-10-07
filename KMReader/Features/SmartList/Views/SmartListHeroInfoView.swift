//
// SmartListHeroInfoView.swift
//
//

import SwiftUI

/// Title, target/visibility line, and summary of the smart list detail hero.
struct SmartListHeroInfoView: View {
  let smartList: SmartList

  @Environment(\.detailHeroCentered) private var heroCentered

  private var secondaryLine: String {
    [smartList.targetDisplayName, smartList.visibilityDisplayName]
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: heroCentered ? .center : .leading, spacing: 6) {
      DetailTitleView(title: smartList.name)

      Text(secondaryLine)
        .font(.subheadline)
        .foregroundColor(.secondary)

      if !smartList.summary.isEmpty {
        Text(smartList.summary)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(heroCentered ? .center : .leading)
          .textSelectionIfAvailable()
      }
    }
    .frame(maxWidth: .infinity, alignment: heroCentered ? .center : .leading)
  }
}
