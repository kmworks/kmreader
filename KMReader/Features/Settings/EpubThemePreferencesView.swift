//
// EpubThemePreferencesView.swift
//
//

#if os(iOS)
  import Foundation
  import SwiftUI

  struct EpubThemePreferencesView: View {
    let inSheet: Bool
    let bookId: String?
    let hasBookThemePreferences: Bool
    let onThemePreferencesSaved: ((EpubThemePreferences) -> Void)?
    let onThemePreferencesCleared: (() -> Void)?

    private let baselineThemePreferences: EpubThemePreferences
    @State private var draft: EpubThemePreferences
    @State private var showCustomFontsSheet: Bool = false
    @State private var showPresetsSheet: Bool = false
    @State private var showSavePresetAlert: Bool = false
    @State private var newPresetName: String = ""
    @State private var fontListRefreshId: UUID = UUID()
    @State private var customFonts: [CustomFontDisplayItem] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

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
      self.baselineThemePreferences = baseline
      self._draft = State(initialValue: baseline)
    }

    private var isBookContext: Bool {
      bookId != nil
    }

    private var navigationTitle: String {
      if isBookContext {
        return String(localized: "Current Book")
      }
      return String(localized: "EPUB Theme")
    }

    private var shouldShowResetToGlobal: Bool {
      isBookContext && hasBookThemePreferences
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

    private var textColor: Color {
      Color(hex: readerTheme.textColorHex) ?? .primary
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

    /// Eager rows rather than a LazyVGrid: inside a self-sizing Form row, the
    /// lazy grid can report two heights for the same width, which UIKit ends
    /// as a recursive layout loop crash.
    private var themePicker: some View {
      let choices = ThemeChoice.allCases
      let rows = stride(from: 0, to: choices.count, by: 2).map {
        Array(choices[$0..<min($0 + 2, choices.count)])
      }

      return VStack(spacing: 12) {
        ForEach(rows, id: \.self) { row in
          HStack(spacing: 12) {
            ForEach(row) { choice in
              themePreviewButton(for: choice)
            }
            ForEach(row.count..<2, id: \.self) { _ in
              Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
          }
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
      Form {
        Section(String(localized: "Presets")) {
          Button {
            showPresetsSheet = true
          } label: {
            HStack {
              Label(String(localized: "Load Preset"), systemImage: "bookmark")
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            }
          }

          Button {
            showSavePresetAlert = true
          } label: {
            Label(String(localized: "Save as Preset"), systemImage: "bookmark.fill")
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
          Picker(String(localized: "Typeface"), selection: $draft.fontFamily) {
            ForEach(FontProvider.allChoices, id: \.id) { choice in
              Text(choice.displayName).tag(choice)
            }
          }
          .id(fontListRefreshId)

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

          Button {
            showCustomFontsSheet = true
          } label: {
            HStack {
              Label(String(localized: "Manage Custom Fonts"), systemImage: "textformat")
              Spacer()
              if !customFonts.isEmpty {
                Text("\(customFonts.count)")
                  .foregroundStyle(.secondary)
              }
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            }
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
              in: 0.00...1.0,
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
      .formStyle(.grouped)
      .animation(.appCurve(0.2), value: draft.advancedLayout)
      .animation(.appCurve(0.2), value: draft.fontWeight != nil)
      .onChange(of: draft.advancedLayout) {
        draft.fontSize = EpubConstants.defaultFontScale
        draft.wordSpacing = EpubConstants.defaultWordSpacing
        draft.paragraphSpacing = EpubConstants.defaultParagraphSpacing
        draft.paragraphIndent = EpubConstants.defaultParagraphIndent
        draft.letterSpacing = EpubConstants.defaultLetterSpacing
        draft.lineHeight = EpubConstants.defaultLineHeight
        draft.textAlignment = .publisherDefault
      }
      .safeAreaInset(edge: .top, spacing: 0) {
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
      }
      .toolbar {
        ToolbarItemGroup(placement: .cancellationAction) {
          if inSheet {
            Button {
              dismiss()
            } label: {
              Label(String(localized: "Close"), systemImage: AppIcon.close)
            }
          }
          Button {
            draft = EpubThemePreferences()
            ErrorManager.shared.notify(message: String(localized: "Reset"))
          } label: {
            Label(String(localized: "Reset"), systemImage: AppIcon.reset)
          }
        }
        ToolbarItemGroup(placement: .confirmationAction) {
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
          .disabled(isSaveDisabled)
        }
      }
      .platformNavigationTitle(navigationTitle)
      .task {
        _ = await loadCustomFonts()
      }
      .sheet(isPresented: $showCustomFontsSheet) {
        CustomFontsSheet()
          .onDisappear {
            Task {
              FontProvider.refresh()
              fontListRefreshId = UUID()

              let loadedFonts = await loadCustomFonts()
              let customFontNames = loadedFonts.map(\.name)
              if let selectedFontName = draft.fontFamily.fontName {
                let isKnownCustomFont = customFontNames.contains(selectedFontName)
                let isKnownChoice = FontProvider.allChoices.contains(where: {
                  $0.fontName == selectedFontName
                })
                if !isKnownCustomFont && !isKnownChoice {
                  draft.fontFamily = .publisher
                }
              }
            }
          }
      }
      .sheet(isPresented: $showPresetsSheet) {
        EpubThemePresetsView(onApply: { preferences in
          draft = preferences
          if !isBookContext {
            AppConfig.epubThemePreferences = preferences
          }
        })
      }
      .alert(
        "Save Preset",
        isPresented: $showSavePresetAlert
      ) {
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
        dismiss()
        return
      }

      AppConfig.epubThemePreferences = draft
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

    private func loadCustomFonts() async -> [CustomFontDisplayItem] {
      do {
        let database = try await DatabaseOperator.database()
        let loadedFonts = try await database.fetchCustomFontDisplayItems()
        if customFonts != loadedFonts {
          customFonts = loadedFonts
        }
        return loadedFonts
      } catch {
        ErrorManager.shared.alert(error: error)
        return customFonts
      }
    }
  }

  enum FontProvider {
    private static var _allChoices: [FontFamilyChoice]?

    static var allChoices: [FontFamilyChoice] {
      if let cached = _allChoices {
        return cached
      }
      return loadFonts()
    }

    static func refresh() {
      _allChoices = nil
    }

    private static func loadFonts() -> [FontFamilyChoice] {
      // Only use custom fonts, not system fonts
      let customFonts = CustomFontStore.shared.fetchCustomFonts()
      let sorted = customFonts.sorted()
      let customChoices = sorted.map { FontFamilyChoice.system($0) }

      _allChoices = [.publisher] + customChoices
      return _allChoices!
    }
  }
#endif
