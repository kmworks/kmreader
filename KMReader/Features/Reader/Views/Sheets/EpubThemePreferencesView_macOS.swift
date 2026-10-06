#if os(macOS)
  import AppKit
  import SwiftUI

  struct EpubThemePreferencesView: View {
    let inSheet: Bool
    let bookId: String?
    let hasBookThemePreferences: Bool
    let onThemePreferencesSaved: ((EpubThemePreferences) -> Void)?
    let onThemePreferencesCleared: (() -> Void)?

    private let baselineThemePreferences: EpubThemePreferences
    @State private var draft: EpubThemePreferences
    @State private var showPresetsSheet: Bool = false
    @State private var showSavePresetAlert: Bool = false
    @State private var newPresetName: String = ""
    @State private var showSystemFontPicker: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(
      inSheet: Bool = false,
      bookId: String? = nil,
      hasBookThemePreferences: Bool = false,
      initialThemePreferences: EpubThemePreferences? = nil,
      onThemePreferencesSaved: ((EpubThemePreferences) -> Void)? = nil,
      onThemePreferencesCleared: (() -> Void)? = nil
    ) {
      self.inSheet = inSheet
      self.bookId = bookId
      self.hasBookThemePreferences = hasBookThemePreferences
      self.onThemePreferencesSaved = onThemePreferencesSaved
      self.onThemePreferencesCleared = onThemePreferencesCleared
      let baseline = initialThemePreferences ?? AppConfig.epubThemePreferences
      baselineThemePreferences = baseline
      _draft = State(initialValue: baseline)
    }

    private var navigationTitle: String {
      bookId == nil ? String(localized: "EPUB Theme") : String(localized: "Current Book")
    }

    private var shouldShowResetToGlobal: Bool {
      bookId != nil && hasBookThemePreferences
    }

    private var isSaveDisabled: Bool {
      draft == baselineThemePreferences
    }

    private var readerTheme: ReaderTheme {
      draft.resolvedTheme(fallbackColorScheme: colorScheme)
    }

    private var resolvedColorScheme: ColorScheme {
      draft.resolvedColorScheme(fallbackColorScheme: colorScheme)
    }

    private var backgroundColor: Color {
      Color(hex: readerTheme.backgroundColorHex) ?? .white
    }

    private var fontWeightEnabled: Binding<Bool> {
      Binding(
        get: { draft.fontWeight != nil },
        set: { isOn in
          if isOn {
            if draft.fontWeight == nil {
              draft.fontWeight = EpubConstants.defaultFontWeight
            }
          } else {
            draft.fontWeight = nil
          }
        }
      )
    }

    private var fontWeightValue: Binding<Double> {
      Binding(
        get: { draft.fontWeight ?? EpubConstants.defaultFontWeight },
        set: { draft.fontWeight = $0 }
      )
    }

    private var fontWeightLabelText: String {
      let valueText: String
      if let fontWeight = draft.fontWeight {
        valueText = "\(Int(fontWeight.rounded()))"
      } else {
        valueText = String(localized: "Default")
      }
      return String.localizedStringWithFormat(String(localized: "Weight: %@"), valueText)
    }

    private var selectedSystemFontName: String? {
      guard case .system(let name) = draft.fontFamily else { return nil }
      return name
    }

    private var selectedPanelFont: NSFont {
      if let fontName = selectedSystemFontName,
        let font = NSFont(name: fontName, size: NSFont.systemFontSize)
      {
        return font
      }
      return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    private var themePicker: some View {
      let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
      ]

      return LazyVGrid(columns: columns, spacing: 12) {
        ForEach(ThemeChoice.allCases) { choice in
          themePreviewButton(for: choice)
        }
      }
      .padding(.vertical, 4)
    }

    @ViewBuilder
    private func themePreviewButton(for choice: ThemeChoice) -> some View {
      let previewTheme = choice.resolvedTheme(for: resolvedColorScheme)
      let isSelected = draft.theme == choice

      Button {
        draft.theme = choice
      } label: {
        Image(systemName: "textformat")
          .font(.system(size: 20))
          .foregroundStyle(previewTheme.textColor)
          .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
          .padding(8)
          .background(previewTheme.backgroundColor)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(isSelected ? Color.primary : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
          )
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    var body: some View {
      VStack(spacing: 0) {
        EpubSettingsPreviewView(preferences: draft)
          .frame(height: 160)
          .background(backgroundColor)
          .overlay(alignment: .bottom) {
            LinearGradient(
              colors: [
                backgroundColor,
                backgroundColor.opacity(0),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(height: 20)
            .offset(y: 20)
            .allowsHitTesting(false)
          }

        Form {
          Section(String(localized: "Presets")) {
            Button(String(localized: "Load Preset")) {
              showPresetsSheet = true
            }

            Button(String(localized: "Save as Preset")) {
              showSavePresetAlert = true
            }
          }

          Section(String(localized: "Theme")) {
            Picker(
              String(localized: "settings.appearance.colorScheme.title"),
              selection: $draft.colorScheme
            ) {
              ForEach(AppColorScheme.allCases) { scheme in
                Text(scheme.label).tag(scheme)
              }
            }

            themePicker
          }

          Section(String(localized: "Font")) {
            HStack {
              Text(String(localized: "Typeface"))
              Spacer()
              Text(draft.fontFamily.displayName)
                .foregroundStyle(.secondary)
            }

            HStack {
              Button(String(localized: "Choose Font")) {
                showSystemFontPicker = true
              }

              Spacer()

              if selectedSystemFontName != nil {
                Button(String(localized: "Publisher Default")) {
                  draft.fontFamily = .publisher
                }
              }
            }

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(fontWeightLabelText)
                Spacer()
                Toggle("", isOn: fontWeightEnabled)
                  .labelsHidden()
              }

              Text(
                String(
                  localized:
                    "Font weight support depends on the current font. Some fonts may ignore this setting or only support part of the range."
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }

            if draft.fontWeight != nil {
              Slider(
                value: fontWeightValue,
                in: EpubConstants.minimumFontWeight...EpubConstants.maximumFontWeight,
                step: EpubConstants.fontWeightStep
              )
            }
          }

          Section(String(localized: "Page")) {
            Picker(String(localized: "Page Layout"), selection: $draft.columnCount) {
              ForEach(EpubColumnCount.allCases) { option in
                Text(option.label)
                  .tag(option)
              }
            }
            .pickerStyle(.segmented)

            LabeledSliderRow(
              label: String(localized: "Page Margins"),
              value: "\(String(format: "%.2f", draft.pageMargins))x",
              binding: $draft.pageMargins,
              in: 0.25...2.0,
              step: 0.05
            )
          }

          Section {
            Toggle(String(localized: "Advanced Layout"), isOn: $draft.advancedLayout)
          }

          if draft.advancedLayout {
            Section(String(localized: "Character & Word")) {
              LabeledSliderRow(
                label: String(localized: "Font Size"),
                value: "\(String(format: "%.2f", draft.fontSize))x",
                binding: $draft.fontSize,
                in: 0.25...4.0,
                step: 0.05
              )

              LabeledSliderRow(
                label: String(localized: "Letter Spacing"),
                value: String(format: "%.2f", draft.letterSpacing),
                binding: $draft.letterSpacing,
                in: 0.0...1.0,
                step: 0.01
              )

              LabeledSliderRow(
                label: String(localized: "Word Spacing"),
                value: String(format: "%.2f", draft.wordSpacing),
                binding: $draft.wordSpacing,
                in: 0.0...1.0,
                step: 0.01
              )
            }

            Section(String(localized: "Line & Paragraph")) {
              VStack(alignment: .leading, spacing: 8) {
                Picker(
                  String(localized: "epub.text_alignment.title", defaultValue: "Text Alignment"),
                  selection: $draft.textAlignment
                ) {
                  ForEach(EpubTextAlignment.allCases) { alignment in
                    Text(alignment.displayName)
                      .tag(alignment)
                  }
                }
                .pickerStyle(.menu)

                Text(
                  String(
                    localized: "epub.text_alignment.justify.description",
                    defaultValue: "Justify automatically enables hyphenation."
                  )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }

              LabeledSliderRow(
                label: String(localized: "Line Height"),
                value: String(format: "%.1f", draft.lineHeight),
                binding: $draft.lineHeight,
                in: 0.5...2.5,
                step: 0.1
              )

              LabeledSliderRow(
                label: String(localized: "Paragraph Spacing"),
                value: String(format: "%.1f", draft.paragraphSpacing),
                binding: $draft.paragraphSpacing,
                in: 0.0...3.0,
                step: 0.1
              )

              LabeledSliderRow(
                label: String(localized: "Paragraph Indent"),
                value: String(format: "%.1f", draft.paragraphIndent),
                binding: $draft.paragraphIndent,
                in: 0.0...8.0,
                step: 0.5
              )
            }
          }

        }
      }
      .formStyle(.grouped)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        controlsBar
      }
      .platformNavigationTitle(navigationTitle)
      .sheet(isPresented: $showPresetsSheet) {
        EpubThemePresetsView(onApply: { preferences in
          draft = preferences
        })
      }
      .background(
        MacSystemFontPickerPresenter(
          isPresented: $showSystemFontPicker,
          initialFont: selectedPanelFont,
          onFontSelected: { font in
            let selectedName = font.familyName ?? font.fontName
            draft.fontFamily = .system(selectedName)
          }
        )
      )
      .alert("Save Preset", isPresented: $showSavePresetAlert) {
        TextField("Preset Name", text: $newPresetName)
        Button("Cancel", role: .cancel) {
          newPresetName = ""
        }
        Button("Save") {
          savePreset()
        }
      } message: {
        Text("Enter a name for this theme preset")
      }
      .animation(.appCurve(0.2), value: draft.advancedLayout)
      .animation(.appCurve(0.2), value: draft.fontWeight != nil)
      .onChange(of: draft.advancedLayout) { _, newValue in
        guard !newValue else { return }
        draft.fontSize = EpubConstants.defaultFontScale
        draft.wordSpacing = EpubConstants.defaultWordSpacing
        draft.paragraphSpacing = EpubConstants.defaultParagraphSpacing
        draft.paragraphIndent = EpubConstants.defaultParagraphIndent
        draft.letterSpacing = EpubConstants.defaultLetterSpacing
        draft.lineHeight = EpubConstants.defaultLineHeight
        draft.textAlignment = .publisherDefault
        draft.fontWeight = nil
      }
    }

    private var controlsBar: some View {
      HStack(spacing: 12) {
        Button {
          resetPreferences()
        } label: {
          Label(String(localized: "Reset"), systemImage: AppIcon.reset)
        }

        Spacer()

        if shouldShowResetToGlobal {
          Button {
            clearBookPreferences()
          } label: {
            Label(String(localized: "Reset to Global"), systemImage: AppIcon.delete)
          }
        }

        Button {
          savePreferences()
        } label: {
          Label(String(localized: "Done"), systemImage: AppIcon.confirm)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSaveDisabled)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(.bar)
    }

    private func resetPreferences() {
      draft = EpubThemePreferences()
      ErrorManager.shared.notify(message: String(localized: "Reset"))
    }

    private func savePreset() {
      let trimmed = newPresetName.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return }

      Task {
        do {
          let database = try await DatabaseOperator.database()
          try await database.createEpubThemePreset(
            name: trimmed,
            preferencesJSON: draft.rawValue
          )
          ErrorManager.shared.notify(message: String(localized: "Preset saved: \(trimmed)"))
          newPresetName = ""
        } catch {
          ErrorManager.shared.alert(error: error)
        }
      }
    }

    private func savePreferences() {
      if let bookId {
        Task {
          try? await DatabaseOperator.database().updateBookEpubThemePreferences(
            bookId: bookId,
            preferences: draft
          )
        }
        onThemePreferencesSaved?(draft)
      } else {
        AppConfig.epubThemePreferences = draft
      }
      dismiss()
    }

    private func clearBookPreferences() {
      guard let bookId else { return }
      Task {
        try? await DatabaseOperator.database().updateBookEpubThemePreferences(
          bookId: bookId,
          preferences: nil
        )
      }
      onThemePreferencesCleared?()
      ErrorManager.shared.notify(message: String(localized: "Reset to Global"))
      dismiss()
    }
  }

  private struct MacSystemFontPickerPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let initialFont: NSFont
    let onFontSelected: (NSFont) -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(isPresented: $isPresented, onFontSelected: onFontSelected)
    }

    func makeNSView(context: Context) -> NSView {
      context.coordinator.bind(initialFont: initialFont)
      return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      context.coordinator.bind(initialFont: initialFont)
      context.coordinator.updatePresentation(isPresented: isPresented)
    }

    final class Coordinator: NSObject {
      private var isPresented: Binding<Bool>
      private let onFontSelected: (NSFont) -> Void
      private var initialFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
      private var isPanelVisible = false

      init(isPresented: Binding<Bool>, onFontSelected: @escaping (NSFont) -> Void) {
        self.isPresented = isPresented
        self.onFontSelected = onFontSelected
        super.init()
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(fontPanelWillClose(_:)),
          name: NSWindow.willCloseNotification,
          object: NSFontPanel.shared
        )
      }

      func bind(initialFont: NSFont) {
        self.initialFont = initialFont
      }

      func updatePresentation(isPresented: Bool) {
        if isPresented {
          presentIfNeeded()
        } else if isPanelVisible {
          NSFontPanel.shared.close()
        }
      }

      private func presentIfNeeded() {
        guard !isPanelVisible else { return }
        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))
        fontManager.setSelectedFont(initialFont, isMultiple: false)
        fontManager.orderFrontFontPanel(nil)
        isPanelVisible = true
      }

      @objc
      private func changeFont(_ sender: NSFontManager) {
        let convertedFont = sender.convert(initialFont)
        initialFont = convertedFont
        onFontSelected(convertedFont)
      }

      @objc
      private func fontPanelWillClose(_ notification: Notification) {
        isPanelVisible = false
        isPresented.wrappedValue = false
      }
    }
  }
#endif
