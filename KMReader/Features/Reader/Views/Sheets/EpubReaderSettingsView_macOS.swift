//
//  EpubReaderSettingsView_macOS.swift
//

#if os(macOS)
  import SwiftUI

  struct EpubReaderSettingsView: View {
    let inSheet: Bool

    init(inSheet: Bool = false) {
      self.inSheet = inSheet
    }

    @AppStorage("epubFlowStyle") private var flowStyle: EpubFlowStyle = .paged
    @AppStorage("epubTapScrollPercentage") private var tapScrollPercentage: Double = AppConfig.epubTapScrollPercentage
    @AppStorage("epubPageTransitionStyle") private var epubPageTransitionStyle: PageTransitionStyle = .scroll
    @AppStorage("animateEpubTapTurns") private var animateEpubTapTurns: Bool = AppConfig.animateEpubTapTurns
    @AppStorage("epubOverlayPreferences") private var epubOverlayPreferences: EpubOverlayPreferences = AppConfig
      .epubOverlayPreferences
    @AppStorage("epubShowKeyboardHelpOverlay") private var showKeyboardHelpOverlay: Bool = AppConfig
      .epubShowKeyboardHelpOverlay
    @AppStorage("epubTapZoneMode") private var epubTapZoneMode: TapZoneMode = AppConfig.epubTapZoneMode
    @AppStorage("epubTapZoneInversionMode") private var epubTapZoneInversionMode: TapZoneInversionMode = AppConfig
      .epubTapZoneInversionMode

    var body: some View {
      if inSheet {
        SheetView(
          title: String(localized: "EPUB Settings"),
          size: .large,
          applyFormStyle: true
        ) {
          settingsForm
        }
        .presentationDragIndicator(.visible)
      } else {
        settingsForm
          .settingsFormWidth()
          .platformNavigationTitle(String(localized: "EPUB Settings"))
      }
    }

    private var settingsForm: some View {
      Form { settingsSections }
        .formStyle(.grouped)
        .animation(.appCurve(0.2), value: flowStyle)
    }

    @ViewBuilder
    private var settingsSections: some View {
      Section(String(localized: "Page Turn")) {
        Picker(String(localized: "epub.reading_flow"), selection: $flowStyle) {
          ForEach(EpubFlowStyle.allCases) { style in Text(style.displayName).tag(style) }
        }
        .pickerStyle(.menu)

        Toggle(isOn: $animateEpubTapTurns) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Animate Page Turns")
            if !inSheet {
              Text("Use animation when tapping zones to turn pages")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        if flowStyle.isPaged {
          VStack(alignment: .leading, spacing: 8) {
            Picker(String(localized: "Page Transition Style"), selection: $epubPageTransitionStyle) {
              ForEach(PageTransitionStyle.epubAvailableCases, id: \.self) { style in Text(style.displayName).tag(style)
              }
            }
            .pickerStyle(.menu)
            if !inSheet {
              Text(epubPageTransitionStyle.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        if flowStyle == .scrolled {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(String(localized: "epub.scrolled.tap_scroll_height"))
              Spacer()
              Text(tapScrollPercentage / 100, format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(.secondary)
            }
            Slider(value: $tapScrollPercentage, in: 25...100, step: 5)
            if !inSheet {
              Text(String(localized: "epub.scrolled.tap_scroll_height.description"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      Section(String(localized: "Tap Zones")) {
        VStack(alignment: .leading, spacing: 8) {
          TapZoneModePicker(
            selection: $epubTapZoneMode,
            tapZoneInversionMode: epubTapZoneInversionMode,
            readingDirection: flowStyle.isPaged ? .ltr : .vertical
          )
          if !inSheet {
            Text("Choose how tap zones are laid out")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if !epubTapZoneMode.isDisabled {
          VStack(alignment: .leading, spacing: 8) {
            Picker("Tap Zone Mirroring", selection: $epubTapZoneInversionMode) {
              ForEach(TapZoneInversionMode.allCases, id: \.self) { mode in Text(mode.displayName).tag(mode) }
            }
            .pickerStyle(.menu)
            if !inSheet {
              Text("Mirror left and right tap zones manually or automatically for RTL reading")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      Section(String(localized: "Reader Overlay")) {
        Toggle(isOn: $showKeyboardHelpOverlay) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Auto-Show Keyboard Help")
            if !inSheet {
              Text("Briefly show keyboard shortcuts when opening the reader")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      EpubOverlayPreferencesEditor(preferences: $epubOverlayPreferences)
    }
  }
#endif
