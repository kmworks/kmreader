//
// MangaToolsSettingsModel.swift
//
//

import Foundation

/// State shared by the manga tools settings sections. The sheet lives here, on
/// the Form that owns the sections: a `.sheet` on a `Group` or `Section` inside
/// a Form is copied onto every row, and the copies fight over one binding.
@MainActor
@Observable
final class MangaToolsSettingsModel {
  var sheet: MangaToolsSheet?
  private(set) var provider: MangaProviderConfig?
  private(set) var detectorArchive: ModelArchive?
  private(set) var recognizerArchive: ModelArchive?

  func archive(for role: MangaModelRole) -> ModelArchive? {
    role == .detector ? detectorArchive : recognizerArchive
  }

  func reload() {
    detectorArchive = MangaModelLibrary.selectedArchive(for: .detector)
    recognizerArchive = MangaModelLibrary.selectedArchive(for: .recognizer)
    Task {
      do {
        provider = try await MangaProviderLibrary.current(
          database: await DatabaseOperator.databaseIfConfigured()
        )
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
