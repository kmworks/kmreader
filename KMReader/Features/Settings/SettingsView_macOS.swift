//
// SettingsView_macOS.swift
//
//

import SwiftUI

#if os(macOS)
  struct SettingsView_macOS: View {
    @State private var selectedSection: SettingsSection? = .appearance
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        List(selection: $selectedSection) {
          Section {
            SettingsSectionRow(section: .appearance)
            SettingsSectionRow(section: .browse)
            SettingsSectionRow(section: .dashboard)
          }

          Section {
            SettingsSectionRow(section: .reading)
            SettingsSectionRow(section: .divinaReader)
            SettingsSectionRow(section: .pdfReader)
            SettingsSectionRow(section: .epubTheme)
            SettingsSectionRow(section: .epubSettings)
          }

          Section {
            SettingsSectionRow(section: .sse)
            SettingsSectionRow(section: .systemFeatures)
            SettingsSectionRow(section: .spotlight)
          }

          Section {
            SettingsSectionRow(section: .network)
            SettingsSectionRow(section: .cache)
            SettingsSectionRow(section: .logs)
          }

          Section {
            SettingsSectionRow(section: .about)
          }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        .navigationTitle("Settings")
      } detail: {
        if let selectedSection {
          NavigationStack {
            detailContent(for: selectedSection)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          Text("Select a setting")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }

    @ViewBuilder
    private func detailContent(for section: SettingsSection) -> some View {
      switch section {
      case .appearance:
        SettingsAppearanceView()
      case .browse:
        SettingsBrowseView()
      case .dashboard:
        SettingsDashboardView()
      case .cache:
        SettingsCacheView()
      case .divinaReader:
        DivinaPreferencesView()
      case .reading:
        ReaderPreferencesView()
      case .pdfReader:
        PdfPreferencesView()
      case .epubTheme:
        EpubThemePreferencesView()
      case .epubSettings:
        EpubReaderSettingsView()
      case .sse:
        SettingsSSEView()
      case .systemFeatures:
        SettingsSystemFeaturesView()
      case .spotlight:
        SettingsSpotlightView()
      case .network:
        SettingsNetworkView()
      case .logs:
        SettingsLogsView()
      case .about:
        SettingsAboutView()
      }
    }
  }
#endif
