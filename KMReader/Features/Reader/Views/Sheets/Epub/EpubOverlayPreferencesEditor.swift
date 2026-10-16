//
// EpubOverlayPreferencesEditor.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  struct EpubOverlayPreferencesEditor: View {
    @Binding var preferences: EpubOverlayPreferences

    var body: some View {
      Section(String(localized: "epub.overlay.reading", defaultValue: "Reading")) {
        textPicker(
          title: String(localized: "epub.overlay.header_left", defaultValue: "Header Left"),
          selection: $preferences.readerHeaderLeading
        )
        textPicker(
          title: String(localized: "epub.overlay.header_center", defaultValue: "Header Center"),
          selection: $preferences.readerHeaderCenter
        )
        textPicker(
          title: String(localized: "epub.overlay.header_right", defaultValue: "Header Right"),
          selection: $preferences.readerHeaderTrailing
        )
        textPicker(
          title: String(localized: "epub.overlay.footer_left", defaultValue: "Footer Left"),
          selection: $preferences.readerFooterLeading
        )
        textPicker(
          title: String(localized: "epub.overlay.footer_center", defaultValue: "Footer Center"),
          selection: $preferences.readerFooterCenter
        )
        textPicker(
          title: String(localized: "epub.overlay.footer_right", defaultValue: "Footer Right"),
          selection: $preferences.readerFooterTrailing
        )
        Toggle(
          String(localized: "epub.overlay.show_reader_progress_bar", defaultValue: "Show Progress Bar"),
          isOn: $preferences.showsReaderProgressBar
        )
      }

      Section(String(localized: "epub.overlay.controls", defaultValue: "Controls")) {
        textPicker(
          title: String(localized: "epub.overlay.header_center", defaultValue: "Header Center"),
          selection: $preferences.controlsHeaderCenter
        )
        textPicker(
          title: String(localized: "epub.overlay.footer_center", defaultValue: "Footer Center"),
          selection: $preferences.controlsFooterCenter
        )
      }
    }

    private func textPicker(
      title: String,
      selection: Binding<EpubOverlayTextItem>
    ) -> some View {
      Picker(title, selection: selection) {
        ForEach(EpubOverlayTextItem.allCases) { item in
          Text(item.displayName).tag(item)
        }
      }
      .pickerStyle(.menu)
    }
  }
#endif
