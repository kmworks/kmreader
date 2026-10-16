#if os(iOS) || os(macOS)
  import SwiftUI

  struct PdfReaderSettingsSheet: View {
    @AppStorage("pdfReaderBackground") private var readerBackground: ReaderBackground = .system
    @AppStorage("pdfShowKeyboardHelpOverlay")
    private var showKeyboardHelpOverlay: Bool = AppConfig.pdfShowKeyboardHelpOverlay
    @AppStorage("showPdfControlsGradientBackground")
    private var showControlsGradientBackground: Bool =
      AppConfig.showPdfControlsGradientBackground
    @AppStorage("showPdfProgressBarWhileReading")
    private var showProgressBarWhileReading: Bool =
      AppConfig.showPdfProgressBarWhileReading

    var body: some View {
      SheetView(
        title: String(localized: "Reader Settings"),
        size: .medium,
        applyFormStyle: true
      ) {
        Form {
          Section(header: Text("Appearance")) {
            Picker("Reader Background", selection: $readerBackground) {
              ForEach(ReaderBackground.allCases, id: \.self) { background in
                Text(background.displayName).tag(background)
              }
            }
            .pickerStyle(.menu)
          }

          Section(header: Text("Reader Overlay")) {
            Toggle(isOn: $showControlsGradientBackground) {
              Text("Controls Gradient Background")
            }

            Toggle(isOn: $showProgressBarWhileReading) {
              Text("Show Progress Bar While Reading")
            }

            Toggle(isOn: $showKeyboardHelpOverlay) {
              Text("Auto-Show Keyboard Help")
            }
          }
        }
      }
      .presentationDragIndicator(.visible)
    }
  }
#endif
