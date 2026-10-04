//
// SettingsDashboardSectionBackgroundToggle.swift
//
//

import SwiftUI

/// The switch for the gradient backdrop drawn behind each dashboard section.
struct SettingsDashboardSectionBackgroundToggle: View {
  @AppStorage("showDashboardSectionGradientBackground") private var showDashboardSectionGradientBackground: Bool =
    AppConfig.showDashboardSectionGradientBackground

  var body: some View {
    Toggle(isOn: $showDashboardSectionGradientBackground) {
      VStack(alignment: .leading, spacing: 4) {
        Text(String(localized: "settings.dashboard.sectionBackground.title"))
        Text(String(localized: "settings.dashboard.sectionBackground.caption"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}
