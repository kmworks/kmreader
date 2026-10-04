//
// EpubThemePresetsView.swift
//
//

import SwiftUI

struct EpubThemePresetsView: View {
  let onApply: ((EpubThemePreferences) -> Void)?

  @Environment(\.dismiss) private var dismiss

  @State private var presets: [EpubThemePresetDisplayItem] = []
  @State private var presetToRename: EpubThemePresetDisplayItem?
  @State private var newName: String = ""

  private var isRenameAlertPresented: Binding<Bool> {
    Binding(
      get: { presetToRename != nil },
      set: { if !$0 { presetToRename = nil } }
    )
  }

  init(onApply: ((EpubThemePreferences) -> Void)? = nil) {
    self.onApply = onApply
  }

  var body: some View {
    SheetView(
      title: String(localized: "Theme Presets"),
      size: .medium,
      applyFormStyle: true
    ) {
      if presets.isEmpty {
        ContentUnavailableView {
          Label("No Theme Presets", systemImage: "bookmark.slash")
        } description: {
          Text(
            "Save your favorite EPUB reading themes for quick access"
          )
        }
      } else {
        List {
          Section(String(localized: "Saved Presets")) {
            ForEach(presets) { preset in
              presetRow(preset)
            }
          }
        }
      }
    }
    .task {
      await loadPresets()
    }
    .alert(
      "Rename Preset",
      isPresented: isRenameAlertPresented
    ) {
      TextField("Preset Name", text: $newName)
      Button("Cancel", role: .cancel) {
        presetToRename = nil
        newName = ""
      }
      Button("Rename") {
        if let preset = presetToRename {
          renamePreset(preset, to: newName)
        }
      }
    }
  }

  @ViewBuilder
  private func presetRow(_ preset: EpubThemePresetDisplayItem) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(preset.name)
          .font(.body)
        Text(preset.updatedAt, style: .relative)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      Button {
        applyPreset(preset)
        dismiss()
      } label: {
        Image(systemName: "arrowshape.turn.up.forward")
          .foregroundColor(.primary)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
      .adaptiveButtonStyle(.plain)
      .accessibilityLabel(Text("Apply Preset"))
    }
    #if os(iOS) || os(macOS)
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) {
          deletePreset(preset)
        } label: {
          Label("Delete", systemImage: "trash")
        }

        Button {
          newName = preset.name
          presetToRename = preset
        } label: {
          Label("Rename", systemImage: "pencil")
        }
      }
    #endif
    .contextMenu {
      Button {
        applyPreset(preset)
        dismiss()
      } label: {
        Label("Apply Preset", systemImage: "arrowshape.turn.up.forward")
      }

      Button {
        newName = preset.name
        presetToRename = preset
      } label: {
        Label("Rename", systemImage: "pencil")
      }

      Divider()

      Button(role: .destructive) {
        deletePreset(preset)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  private func applyPreset(_ preset: EpubThemePresetDisplayItem) {
    if let preferences = preset.preferences {
      if let onApply {
        onApply(preferences)
      } else {
        AppConfig.epubThemePreferences = preferences
      }
      ErrorManager.shared.notify(message: String(localized: "Preset applied: \(preset.name)"))
    }
  }

  private func deletePreset(_ preset: EpubThemePresetDisplayItem) {
    Task {
      do {
        let database = try await DatabaseOperator.database()
        try await database.deleteEpubThemePreset(id: preset.id)
        await loadPresets()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func renamePreset(_ preset: EpubThemePresetDisplayItem, to newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }

    Task {
      do {
        let database = try await DatabaseOperator.database()
        try await database.renameEpubThemePreset(id: preset.id, name: trimmed)
        await loadPresets()
        presetToRename = nil
        self.newName = ""
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  private func loadPresets() async {
    do {
      let database = try await DatabaseOperator.database()
      let loadedPresets = try await database.fetchEpubThemePresetDisplayItems()
      if presets != loadedPresets {
        presets = loadedPresets
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
