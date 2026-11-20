//
// SeriesBatchEditSheet.swift
//
//

import SwiftUI

struct SeriesBatchEditSheet: View {
  let seriesIds: [String]
  let onCompleted: (Set<String>) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var enabledFields: Set<SeriesBatchSharedField> = []
  @State private var sharedLocks: [SeriesBatchSharedField: Bool] = [:]
  @State private var status = SeriesStatus.ongoing
  @State private var readingDirection: ReadingDirection?
  @State private var publisher = ""
  @State private var language = ""
  @State private var ageRating = ""
  @State private var genres: [String] = []
  @State private var tags: [String] = []
  @State private var sharingLabels: [String] = []
  @State private var batchController = BatchOperationController()

  private var canSave: Bool {
    !enabledFields.isEmpty && !batchController.isRunning
  }

  var body: some View {
    SheetView(
      title: String(localized: "batch.series.editTitle \(seriesIds.count)"),
      size: .large,
      showsCloseButton: !batchController.isRunning,
      applyFormStyle: true
    ) {
      Form {
        Section {
          Text("batch.series.sharedHint \(seriesIds.count)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        BatchMetadataField(
          title: String(localized: "Status"),
          isEnabled: enabledBinding(for: .status),
          isLocked: lockBinding(for: .status)
        ) {
          Picker("Status", selection: $status) {
            ForEach(SeriesStatus.allCases, id: \.self) { status in
              Text(status.displayName).tag(status)
            }
          }
        }

        BatchMetadataField(
          title: String(localized: "Reading Direction"),
          hint: String(localized: "batch.series.directionNotSet"),
          isEnabled: enabledBinding(for: .readingDirection),
          isLocked: lockBinding(for: .readingDirection)
        ) {
          Picker("Reading Direction", selection: $readingDirection) {
            Text("Not Set").tag(ReadingDirection?.none)
            ForEach(ReadingDirection.allCases, id: \.self) { direction in
              Text(direction.displayName).tag(ReadingDirection?.some(direction))
            }
          }
        }

        BatchMetadataField(
          title: String(localized: "Publisher"),
          isEnabled: enabledBinding(for: .publisher),
          isLocked: lockBinding(for: .publisher)
        ) {
          TextField("Publisher", text: $publisher)
        }

        BatchMetadataField(
          title: String(localized: "Language"),
          hint: String(localized: "batch.metadata.emptyClears"),
          isEnabled: enabledBinding(for: .language),
          isLocked: lockBinding(for: .language)
        ) {
          LanguagePicker(selectedLanguage: $language)
        }

        BatchMetadataField(
          title: String(localized: "Age Rating"),
          hint: String(localized: "batch.metadata.emptyClears"),
          isEnabled: enabledBinding(for: .ageRating),
          isLocked: lockBinding(for: .ageRating)
        ) {
          TextField("Age Rating", text: $ageRating)
            #if os(iOS)
              .keyboardType(.numberPad)
            #endif
        }

        BatchMetadataField(
          title: String(localized: "Genres"),
          hint: String(localized: "batch.metadata.replacesAll"),
          isEnabled: enabledBinding(for: .genres),
          isLocked: lockBinding(for: .genres)
        ) {
          BatchStringListEditor(placeholder: String(localized: "Genre"), values: $genres)
        }

        BatchMetadataField(
          title: String(localized: "Tags"),
          hint: String(localized: "batch.metadata.replacesAll"),
          isEnabled: enabledBinding(for: .tags),
          isLocked: lockBinding(for: .tags)
        ) {
          BatchStringListEditor(placeholder: String(localized: "Tag"), values: $tags)
        }

        BatchMetadataField(
          title: String(localized: "Sharing Labels"),
          hint: String(localized: "batch.metadata.replacesAll"),
          isEnabled: enabledBinding(for: .sharingLabels),
          isLocked: lockBinding(for: .sharingLabels)
        ) {
          BatchStringListEditor(
            placeholder: String(localized: "Label"),
            values: $sharingLabels
          )
        }
      }
      .disabled(batchController.isRunning)
    } controls: {
      Button(action: saveChanges) {
        if batchController.isRunning {
          Label(
            "batch.progress \(batchController.completedCount) \(batchController.totalCount)",
            systemImage: "arrow.triangle.2.circlepath"
          )
        } else {
          Label("Save", systemImage: AppIcon.confirm)
        }
      }
      .disabled(!canSave)
    }
  }

  private func enabledBinding(for field: SeriesBatchSharedField) -> Binding<Bool> {
    Binding(
      get: { enabledFields.contains(field) },
      set: { enabled in
        if enabled {
          enabledFields.insert(field)
          if sharedLocks[field] == nil {
            sharedLocks[field] = true
          }
        } else {
          enabledFields.remove(field)
        }
      }
    )
  }

  private func lockBinding(for field: SeriesBatchSharedField) -> Binding<Bool> {
    Binding(
      get: { sharedLocks[field] ?? true },
      set: { sharedLocks[field] = $0 }
    )
  }

  private func saveChanges() {
    guard canSave else { return }
    if enabledFields.contains(.ageRating), !isValidAgeRating(ageRating) {
      ErrorManager.shared.alert(message: String(localized: "batch.validation.invalidAgeRating"))
      return
    }
    let metadata = makeMetadata()

    Task {
      let outcome = await batchController.run(ids: seriesIds) { seriesId in
        try await SeriesService.updateSeriesMetadata(seriesId: seriesId, metadata: metadata)
      }

      if !outcome.succeeded.isEmpty {
        await SyncService.syncVisitedItems(
          bookIds: [],
          seriesIds: Set(outcome.succeeded)
        )
        for seriesId in outcome.succeeded {
          await ContentProjectionNotifier.postSeriesDidChange(
            seriesId: seriesId,
            reason: .content
          )
        }
        await DashboardSectionRefreshNotifier.postSeriesContentChanged(
          source: .manual,
          reason: "Series metadata batch updated"
        )
      }

      if let firstError = outcome.firstError {
        ErrorManager.shared.alertBatchFailure(
          failedCount: outcome.failed.count,
          totalCount: outcome.succeeded.count + outcome.failed.count,
          error: firstError
        )
      } else {
        ErrorManager.shared.notify(
          message: String(localized: "batch.series.updated \(outcome.succeeded.count)")
        )
      }

      onCompleted(Set(outcome.failed))
      dismiss()
    }
  }

  private func isValidAgeRating(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    guard let rating = Int(trimmed) else { return false }
    return rating >= 0
  }

  private func makeMetadata() -> [String: Any] {
    var metadata: [String: Any] = [:]

    if enabledFields.contains(.status) {
      metadata["status"] = status.apiValue
      metadata["statusLock"] = sharedLocks[.status] ?? true
    }
    if enabledFields.contains(.readingDirection) {
      if let readingDirection {
        metadata["readingDirection"] = readingDirection.rawValue
      } else {
        metadata["readingDirection"] = NSNull()
      }
      metadata["readingDirectionLock"] = sharedLocks[.readingDirection] ?? true
    }
    if enabledFields.contains(.publisher) {
      metadata["publisher"] = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
      metadata["publisherLock"] = sharedLocks[.publisher] ?? true
    }
    if enabledFields.contains(.language) {
      metadata["language"] = language.trimmingCharacters(in: .whitespacesAndNewlines)
      metadata["languageLock"] = sharedLocks[.language] ?? true
    }
    if enabledFields.contains(.ageRating) {
      let trimmed = ageRating.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        metadata["ageRating"] = NSNull()
      } else {
        metadata["ageRating"] = Int(trimmed) ?? 0
      }
      metadata["ageRatingLock"] = sharedLocks[.ageRating] ?? true
    }
    if enabledFields.contains(.genres) {
      metadata["genres"] = genres
      metadata["genresLock"] = sharedLocks[.genres] ?? true
    }
    if enabledFields.contains(.tags) {
      metadata["tags"] = tags
      metadata["tagsLock"] = sharedLocks[.tags] ?? true
    }
    if enabledFields.contains(.sharingLabels) {
      metadata["sharingLabels"] = sharingLabels
      metadata["sharingLabelsLock"] = sharedLocks[.sharingLabels] ?? true
    }

    return metadata
  }
}
