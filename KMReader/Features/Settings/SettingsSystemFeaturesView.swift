//
// SettingsSystemFeaturesView.swift
//
//

import SwiftUI

struct SettingsSystemFeaturesView: View {
  #if os(iOS) || os(macOS)
    @AppStorage("enableBrowseHandoff") private var enableBrowseHandoff: Bool = true
    @AppStorage("enableReaderHandoff") private var enableReaderHandoff: Bool = false
  #endif

  var body: some View {
    Form {
      #if os(iOS) || os(macOS)
        Section(header: Text(String(localized: "settings.network.handoff"))) {
          Toggle(isOn: $enableBrowseHandoff) {
            VStack(alignment: .leading, spacing: 4) {
              Text(String(localized: "settings.network.handoff.browse.title"))
              Text(String(localized: "settings.network.handoff.browse.caption"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Toggle(isOn: $enableReaderHandoff) {
            VStack(alignment: .leading, spacing: 4) {
              Text(String(localized: "settings.network.handoff.reader.title"))
              Text(String(localized: "settings.network.handoff.reader.caption"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      #endif
    }
    .formStyle(.grouped)
    .settingsFormWidth()
    .platformNavigationTitle(SettingsSection.systemFeatures.title)
  }
}
