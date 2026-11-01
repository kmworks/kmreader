import SwiftUI

struct PanelModelManagementView: View {
  @AppStorage("panelZoomFillFactor") private var panelZoomFillFactor: Double = 0.9

  @State private var catalog: ModelCatalog?
  @State private var installedArchive: ModelArchive?
  @State private var installedBytes: Int64?
  @State private var isLoadingCatalog = false
  @State private var preparingStorageKey: String?
  @State private var downloadProgress: Double?
  @State private var showsDeleteConfirmation = false

  private var availableArchive: ModelArchive? {
    guard let catalog else { return nil }
    return PanelModelLibrary.catalogArchive(in: catalog)
  }

  private var updateAvailable: Bool {
    guard let availableArchive, let installedArchive else { return false }
    return availableArchive.version > installedArchive.version
  }

  private var showsDownload: Bool {
    guard availableArchive != nil else { return false }
    return installedArchive == nil || updateAvailable
  }

  var body: some View {
    Form {
      Section(
        header: Text("Installed Model"),
        footer: Text("Panel Mode downloads and prepares the model automatically when first enabled.")
      ) {
        if let installedArchive {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(installedArchive.name)
              Text(detailText(for: installedArchive))
                .font(.caption)
                .foregroundStyle(.secondary)
              if let comment = installedArchive.comment, !comment.isEmpty {
                Text(comment)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            Button(role: .destructive) {
              showsDeleteConfirmation = true
            } label: {
              Image(systemName: AppIcon.delete)
            }
            .buttonStyle(.borderless)
            .disabled(preparingStorageKey != nil)
          }
        } else {
          Text("No model downloaded")
            .foregroundStyle(.secondary)
        }
      }

      if showsDownload, let availableArchive {
        Section(header: Text(updateAvailable ? "Model Update" : "Available Model")) {
          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(availableArchive.name)
              Text(detailText(for: availableArchive))
                .font(.caption)
                .foregroundStyle(.secondary)
              if preparingStorageKey == availableArchive.storageKey {
                ProgressView(value: downloadProgress ?? 0)
              }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
              Text(availableArchive.bytes.map { formatBytes(Int64($0)) } ?? String(localized: "Unknown"))
                .font(.caption)
                .foregroundStyle(.secondary)
              Button {
                prepare(availableArchive)
              } label: {
                if preparingStorageKey == availableArchive.storageKey {
                  LoadingIcon()
                } else {
                  Text(updateAvailable ? "Update" : "Download")
                }
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(preparingStorageKey != nil)
            }
          }
          .padding(.vertical, 4)
        }
      }

      #if os(iOS)
        Section(header: Text("Reading")) {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Panel Zoom Fill")
              Spacer()
              Text(String(format: "%.0f%%", panelZoomFillFactor * 100))
                .foregroundStyle(.secondary)
            }
            Slider(value: $panelZoomFillFactor, in: 0.75...1.0, step: 0.05)
          }
        }
      #endif

      Section(
        header: HStack {
          Text("Catalog")
          Spacer()
          Button(action: refreshCatalog) {
            Label(String(localized: "Refresh Catalog"), systemImage: AppIcon.refresh)
              .labelStyle(.iconOnly)
              .symbolEffect(.pulse, options: .repeating, isActive: isLoadingCatalog)
          }
          .buttonStyle(.borderless)
          .disabled(isLoadingCatalog || preparingStorageKey != nil)
        },
        footer: Text(
          "The panel detector is trained on Manga109-s. Its attribution and citations are included in the model package and the open source licenses page."
        )
      ) {
        Text(ModelLibraryConfiguration.defaultCatalogURL)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .onAppear {
      catalog = .cached
      reloadInstalledModel()
      refreshCatalog()
    }
    .alert(String(localized: "Delete Model"), isPresented: $showsDeleteConfirmation) {
      Button(String(localized: "Delete"), role: .destructive, action: deleteModel)
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(installedArchive?.name ?? "")
    }
  }

  private func detailText(for archive: ModelArchive) -> String {
    let version = String(localized: "Version \(archive.version)")
    let size =
      archive.storageKey == installedArchive?.storageKey
      ? installedBytes.map(formatBytes) : archive.bytes.map { formatBytes(Int64($0)) }
    return [version, archive.license, size].compactMap { $0 }.joined(separator: " · ")
  }

  private func refreshCatalog() {
    guard !isLoadingCatalog else { return }
    isLoadingCatalog = true
    Task {
      do {
        catalog = try await ModelCatalogService.fetch()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isLoadingCatalog = false
    }
  }

  private func prepare(_ archive: ModelArchive) {
    guard preparingStorageKey == nil else { return }
    preparingStorageKey = archive.storageKey
    downloadProgress = nil
    Task {
      do {
        _ = try await PanelModelService.shared.prepare(archive: archive) { received, expected in
          Task { @MainActor in
            downloadProgress = expected.map { min(1, Double(received) / Double($0)) }
          }
        }
        reloadInstalledModel()
      } catch is CancellationError {
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      preparingStorageKey = nil
      downloadProgress = nil
    }
  }

  private func deleteModel() {
    guard let installedArchive, preparingStorageKey == nil else { return }
    preparingStorageKey = installedArchive.storageKey
    Task {
      do {
        try await PanelModelService.shared.clear(archive: installedArchive)
        reloadInstalledModel()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      preparingStorageKey = nil
    }
  }

  private func reloadInstalledModel() {
    guard let storage = try? ModelStorage.shared else {
      installedArchive = nil
      installedBytes = nil
      return
    }
    PanelModelLibrary.reconcile(storage: storage)
    installedArchive = PanelModelLibrary.installedArchive()
    installedBytes = installedArchive.map {
      MangaModelManager.status(storage: storage.storage(for: $0), archive: $0).totalBytes
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
