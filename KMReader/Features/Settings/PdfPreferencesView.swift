#if os(iOS) || os(macOS)
  import SwiftUI

  struct PdfPreferencesView: View {
    @AppStorage("useNativePdfReader") private var useNativePdfReader: Bool = true
    @AppStorage("pdfReaderBackground") private var readerBackground: ReaderBackground = .system
    @AppStorage("pdfDefaultReadingDirection")
    private var defaultReadingDirection: ReadingDirection = .ltr
    @AppStorage("pdfForceDefaultReadingDirection")
    private var forceDefaultReadingDirection: Bool = false
    @AppStorage("pdfPagePresentation")
    private var pagePresentation: PdfPagePresentation = AppConfig.pdfPagePresentation
    @AppStorage("pdfIsolateCoverPage")
    private var soloCoverPage: Bool = true
    @AppStorage("pdfShowKeyboardHelpOverlay")
    private var showKeyboardHelpOverlay: Bool = AppConfig.pdfShowKeyboardHelpOverlay
    @AppStorage("showPdfControlsGradientBackground")
    private var showControlsGradientBackground: Bool =
      AppConfig.showPdfControlsGradientBackground
    @AppStorage("showPdfProgressBarWhileReading")
    private var showProgressBarWhileReading: Bool =
      AppConfig.showPdfProgressBarWhileReading
    @AppStorage("pdfOfflineRenderQuality")
    private var pdfOfflineRenderQuality: PdfOfflineRenderQuality = AppConfig.pdfOfflineRenderQuality

    var body: some View {
      Form {
        Section {
          Toggle(isOn: $useNativePdfReader) {
            Text("Use Native PDF Reader")
          }

          Text(
            useNativePdfReader
              ? "Native PDF Reader uses the system PDF engine and works best for text-heavy PDF books."
              : "PDF books open with DIVINA Reader. Recommended for comic and manga PDFs, especially when offline-downloaded pages are rendered as images."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        if useNativePdfReader {
          Section(header: Text("Default Reading Options")) {
            VStack(alignment: .leading, spacing: 8) {
              Picker("Preferred Direction", selection: $defaultReadingDirection) {
                ForEach(ReadingDirection.pdfAvailableCases, id: \.self) { direction in
                  Label(direction.displayName, systemImage: direction.icon)
                    .tag(direction)
                }
              }
              .pickerStyle(.menu)

              Text("Used when a book or series doesn't specify a reading direction")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Toggle(isOn: $forceDefaultReadingDirection) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Force Default Reading Direction")
                Text("Ignore book and series metadata and always use the preferred direction")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            VStack(alignment: .leading, spacing: 8) {
              Picker("Page Presentation", selection: $pagePresentation) {
                ForEach(PdfPagePresentation.allCases, id: \.self) { presentation in
                  Label(presentation.displayName, systemImage: presentation.icon)
                    .tag(presentation)
                }
              }
              .pickerStyle(.menu)

              Text(pagePresentation.detailText)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if pagePresentation.supportsCoverSolo {
              Toggle(isOn: $soloCoverPage) {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Solo Cover Page")
                  Text("Show the first page alone before entering dual-page spread")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }
            }
          }

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
              VStack(alignment: .leading, spacing: 4) {
                Text("Controls Gradient Background")
                Text("Add a gradient behind reader controls for better contrast over pages.")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            Toggle(isOn: $showProgressBarWhileReading) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Show Progress Bar While Reading")
                Text("Keep book progress pinned to the bottom until reader controls are shown.")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            Toggle(isOn: $showKeyboardHelpOverlay) {
              VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Show Keyboard Help")
                Text("Briefly show keyboard shortcuts when opening the reader")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        }

        if !useNativePdfReader {
          Section(header: Text("Offline DIVINA Rendering")) {
            VStack(alignment: .leading, spacing: 8) {
              Picker("Render Quality", selection: $pdfOfflineRenderQuality) {
                ForEach(PdfOfflineRenderQuality.allCases, id: \.self) { quality in
                  Text(quality.displayName).tag(quality)
                }
              }
              .pickerStyle(.menu)

              Text("Used for offline-downloaded PDF books rendered by DIVINA Reader.")
                .font(.caption)
                .foregroundColor(.secondary)

              Text(pdfOfflineRenderQuality.detailText)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }
      .onAppear {
        if defaultReadingDirection == .webtoon {
          defaultReadingDirection = .vertical
        }
      }
      .animation(.appCurve(0.2), value: useNativePdfReader)
      .formStyle(.grouped)
      .platformNavigationTitle(SettingsSection.pdfReader.title)
    }
  }
#endif
