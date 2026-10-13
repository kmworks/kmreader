import SwiftUI

struct MangaModelManagementView: View {
  let role: MangaModelRole

  @AppStorage("modelLibrary") private var libraryConfiguration = ModelLibraryConfiguration()

  @State private var catalog: ModelCatalog?
  @State private var downloadedArchives: [ModelArchive] = []
  @State private var statuses: [String: MangaModelStorageStatus] = [:]
  @State private var isLoadingCatalog = false
  @State private var showsCatalogEditor = false
  @State private var catalogURLDraft = ""
  @State private var preparingStorageKey: String?
  @State private var downloadProgress: Double?
  @State private var deletingStorageKey: String?
  @State private var archiveToDelete: ModelArchive?
  @State private var showsDeleteConfirmation = false

  private var isModelOperationInProgress: Bool {
    preparingStorageKey != nil || deletingStorageKey != nil
  }

  private var availableArchives: [ModelArchive] {
    let downloadedKeys = Set(downloadedArchives.map(\.storageKey))
    return (catalog?.models(for: .mangaOCR) ?? []).filter {
      !downloadedKeys.contains($0.storageKey) && MangaModelSet.supports($0, for: role)
    }
  }

  private var selectableArchives: [ModelArchive] {
    downloadedArchives.filter { MangaModelSet.supports($0, for: role) }
  }

  private var canSaveCatalogURL: Bool {
    let value = catalogURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      components.host?.isEmpty == false
    else {
      return false
    }
    return true
  }

  var body: some View {
    Form {
      Section(
        header: Text(role.title),
        footer: Text(
          "Use one model for both roles, or mix a detection model with a different recognition model.")
      ) {
        if selectableArchives.isEmpty {
          Text("No models downloaded")
            .foregroundStyle(.secondary)
        }
        ForEach(selectableArchives, id: \.storageKey) { archive in
          Button {
            MangaModelLibrary.select(archive, for: role)
            reloadDownloadedModels()
          } label: {
            HStack(spacing: 12) {
              Image(systemName: isSelected(archive) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected(archive) ? Color.accentColor : Color.secondary)
              VStack(alignment: .leading, spacing: 4) {
                Text(archive.name)
                MangaModelCapabilityChips(archive: archive)
                if let comment = archive.comment, !comment.isEmpty {
                  Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              Spacer()
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }

      Section(
        header: Text("Downloaded"),
        footer: Text("Downloaded models remain available when the catalog changes.")
      ) {
        if downloadedArchives.isEmpty {
          Text("No models downloaded")
            .foregroundStyle(.secondary)
        }
        ForEach(downloadedArchives, id: \.storageKey) { archive in
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(archive.name)
              Text(detailText(for: archive))
                .font(.caption)
                .foregroundStyle(.secondary)
              MangaModelCapabilityChips(archive: archive)
              if let comment = archive.comment, !comment.isEmpty {
                Text(comment)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            if preparingStorageKey == archive.storageKey || deletingStorageKey == archive.storageKey {
              LoadingIcon()
            } else {
              Button(role: .destructive) {
                archiveToDelete = archive
                showsDeleteConfirmation = true
              } label: {
                Image(systemName: AppIcon.delete)
              }
              .buttonStyle(.borderless)
              .disabled(isModelOperationInProgress)
            }
          }
        }
      }

      Section(header: Text("Available Models")) {
        if availableArchives.isEmpty && !isLoadingCatalog {
          Text("No additional models in this catalog")
            .foregroundStyle(.secondary)
        }
        ForEach(availableArchives, id: \.storageKey) { archive in
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(archive.name)
              Text(detailText(for: archive))
                .font(.caption)
                .foregroundStyle(.secondary)
              MangaModelCapabilityChips(archive: archive)
              if let comment = archive.comment, !comment.isEmpty {
                Text(comment)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              if preparingStorageKey == archive.storageKey {
                ProgressView(value: downloadProgress ?? 0)
              }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
              Text(archive.bytes.map { formatBytes(Int64($0)) } ?? String(localized: "Unknown"))
                .font(.caption)
                .foregroundStyle(.secondary)
              Button {
                prepare(archive)
              } label: {
                if preparingStorageKey == archive.storageKey {
                  LoadingIcon()
                } else {
                  Image(systemName: AppIcon.download)
                    .accessibilityLabel(Text("Download & Use"))
                }
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(isModelOperationInProgress)
            }
          }
          .padding(.vertical, 4)
        }
      }

      Section(
        header: HStack {
          Text("Catalog")
          Spacer()
          Button {
            refreshCatalog()
          } label: {
            Label(String(localized: "Refresh Catalog"), systemImage: AppIcon.refresh)
              .labelStyle(.iconOnly)
              .symbolEffect(.pulse, options: .repeating, isActive: isLoadingCatalog)
          }
          .buttonStyle(.borderless)
          .disabled(isLoadingCatalog || isModelOperationInProgress)
        },
        footer: Text("The default catalog is recommended. Custom catalogs must use HTTPS.")
      ) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Catalog URL")
            Text(libraryConfiguration.catalogURL)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Spacer()
          Button(String(localized: "Edit"), action: beginCatalogEdit)
            .buttonStyle(.borderless)
            .disabled(isLoadingCatalog)
        }
      }
    }
    .onAppear {
      catalog = .cached
      reloadDownloadedModels()
      refreshCatalog()
    }
    .sheet(isPresented: $showsCatalogEditor) {
      SheetView(title: String(localized: "Catalog URL"), size: .medium, applyFormStyle: true) {
        Form {
          Section(
            footer: Text("The default catalog is recommended. Custom catalogs must use HTTPS.")
          ) {
            TextField(String(localized: "Catalog URL"), text: $catalogURLDraft)
              .textContentType(.URL)
              .autocorrectionDisabled()
              #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
              #endif
              .onSubmit(saveCatalogURL)
          }
        }
      } controls: {
        Button {
          catalogURLDraft = ModelLibraryConfiguration.defaultCatalogURL
          saveCatalogURL()
        } label: {
          Label(String(localized: "Reset to Default"), systemImage: AppIcon.reset)
            .labelStyle(.iconOnly)
        }
        Button(String(localized: "Save"), action: saveCatalogURL)
          .disabled(!canSaveCatalogURL)
      }
    }
    .alert(String(localized: "Delete Model"), isPresented: $showsDeleteConfirmation) {
      Button(String(localized: "Delete"), role: .destructive) {
        if let archiveToDelete {
          delete(archiveToDelete)
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(archiveToDelete?.name ?? "")
    }
  }

  private func isSelected(_ archive: ModelArchive) -> Bool {
    let key =
      libraryConfiguration.selectedStorageKeys[role.selectionStorageKey]
      ?? libraryConfiguration.selectedStorageKeys[ModelPurpose.mangaOCR.rawValue] ?? ""
    return key == archive.storageKey
  }

  private func beginCatalogEdit() {
    guard !isLoadingCatalog else { return }
    catalogURLDraft = libraryConfiguration.catalogURL
    showsCatalogEditor = true
  }

  private func cancelCatalogEdit() {
    catalogURLDraft = ""
    showsCatalogEditor = false
  }

  private func saveCatalogURL() {
    guard canSaveCatalogURL else { return }
    libraryConfiguration.catalogURL = catalogURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    libraryConfiguration.catalog = nil
    catalog = nil
    cancelCatalogEdit()
    refreshCatalog()
  }

  private func detailText(for archive: ModelArchive) -> String {
    let version = String(localized: "Version \(archive.version)")
    let size = statuses[archive.storageKey].map { formatBytes($0.totalBytes) }
    return [version, archive.license, size].compactMap { $0 }.joined(separator: " · ")
  }

  private func refreshCatalog() {
    guard !isLoadingCatalog else { return }
    isLoadingCatalog = true
    Task {
      do {
        catalog = try await ModelCatalogService.fetch()
        reloadDownloadedModels()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isLoadingCatalog = false
    }
  }

  private func prepare(_ archive: ModelArchive) {
    guard !isModelOperationInProgress else { return }
    preparingStorageKey = archive.storageKey
    downloadProgress = nil
    Task {
      do {
        try await MangaTranslationService.shared.prepareModels(archive: archive) { received, expected in
          Task { @MainActor in
            downloadProgress = expected.map { min(1, Double(received) / Double($0)) }
          }
        }
        MangaModelLibrary.select(archive)
        reloadDownloadedModels()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      preparingStorageKey = nil
      downloadProgress = nil
    }
  }

  private func delete(_ archive: ModelArchive) {
    guard !isModelOperationInProgress else { return }
    deletingStorageKey = archive.storageKey
    Task {
      do {
        try await MangaTranslationService.shared.clearModels(
          storage: ModelStorage.shared,
          archive: archive
        )
        reloadDownloadedModels()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      deletingStorageKey = nil
    }
  }

  private func reloadDownloadedModels() {
    guard let storage = try? ModelStorage.shared else {
      downloadedArchives = []
      statuses = [:]
      return
    }
    MangaModelLibrary.reconcile(storage: storage)
    downloadedArchives = MangaModelLibrary.downloadedArchives()
    statuses = Dictionary(
      downloadedArchives.map {
        ($0.storageKey, MangaModelManager.status(storage: storage.storage(for: $0), archive: $0))
      },
      uniquingKeysWith: { first, _ in first }
    )
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
