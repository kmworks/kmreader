//
// SettingsSystemFeaturesView.swift
//
//

import SwiftUI

struct SettingsSystemFeaturesView: View {
  #if os(iOS) || os(macOS)
    @AppStorage("enableBrowseHandoff") private var enableBrowseHandoff: Bool = true
    @AppStorage("enableReaderHandoff") private var enableReaderHandoff: Bool = false
    @AppStorage("enableSpotlightIndexing") private var enableSpotlightIndexing: Bool = true
    @AppStorage("enableSpotlightBookIndexing") private var enableSpotlightBookIndexing: Bool = true
    @AppStorage("enableSpotlightSeriesIndexing") private var enableSpotlightSeriesIndexing: Bool = false
    @State private var libraries: [LibraryInfo] = []
    @State private var indexedLibraryIds: Set<String> = []
    @State private var indexAllLibraries = true

    private var currentInstanceId: String {
      AppConfig.current.instanceId
    }

    private var allLibraryIds: Set<String> {
      Set(libraries.map(\.id))
    }

    private var indexAllLibrariesBinding: Binding<Bool> {
      Binding(
        get: { indexAllLibraries },
        set: { newValue in
          withAnimation(.appCurve(0.2)) {
            indexAllLibraries = newValue
            if newValue {
              indexedLibraryIds = allLibraryIds
            }
          }
          persistSelection()
        }
      )
    }
  #endif

  var body: some View {
    Form {
      #if os(iOS) || os(macOS)
        Section(header: Text(String(localized: "settings.network.handoff"))) {
          Toggle(isOn: $enableBrowseHandoff) {
            VStack(alignment: .leading, spacing: 4) {
              Text(String(localized: "settings.network.handoff.browse.title"))
              Text(String(localized: "settings.network.handoff.browse.caption"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Toggle(isOn: $enableReaderHandoff) {
            VStack(alignment: .leading, spacing: 4) {
              Text(String(localized: "settings.network.handoff.reader.title"))
              Text(String(localized: "settings.network.handoff.reader.caption"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        Section {
          Toggle(isOn: $enableSpotlightIndexing) {
            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 6) {
                Image(systemName: AppIcon.search)
                Text(String(localized: "Enable Spotlight Indexing"))
              }
              Text(
                String(
                  localized:
                    "When disabled, no books will be indexed in Spotlight."
                )
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }
        } header: {
          Text(String(localized: "Spotlight"))
        }

        if enableSpotlightIndexing {
          Section {
            Toggle(isOn: $enableSpotlightBookIndexing) {
              Label(String(localized: "Index Books"), systemImage: ContentIcon.book)
            }
            Toggle(isOn: $enableSpotlightSeriesIndexing) {
              Label(String(localized: "Index Series"), systemImage: ContentIcon.series)
            }
          } header: {
            Text(String(localized: "Content Types"))
          } footer: {
            Text(
              String(
                localized: "Choose which entities should appear in Spotlight results."
              )
            )
          }

          Section {
            Toggle(isOn: indexAllLibrariesBinding) {
              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                  Image(systemName: "square.stack.3d.up")
                  Text(String(localized: "Index all libraries"))
                }
                Text(
                  String(
                    localized:
                      "When enabled, Spotlight indexes downloaded books from all libraries in the current server."
                  )
                )
                .font(.caption)
                .foregroundColor(.secondary)
              }
            }
          } header: {
            Text(String(localized: "Index Scope"))
          }

          if !indexAllLibraries {
            Section {
              ForEach(libraries) { library in
                Button {
                  toggleLibrary(library.id)
                } label: {
                  HStack {
                    Text(library.name)
                      .foregroundStyle(.primary)
                    Spacer()
                    if indexedLibraryIds.contains(library.id) {
                      Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                    } else {
                      Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                    }
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            } header: {
              Text(String(localized: "Indexed Libraries"))
            } footer: {
              Text(
                String(
                  localized:
                    "Only selected libraries will be indexed. Changes affect future indexing and instance-switch reindexing."
                )
              )
            }

            Section {
              Button(String(localized: "Select All Libraries")) {
                indexedLibraryIds = allLibraryIds
                persistSelection()
              }
              Button(String(localized: "Clear Selection"), role: .destructive) {
                indexedLibraryIds.removeAll()
                persistSelection()
              }
            }
          }
        }
      #endif
    }
    .formStyle(.grouped)
    .platformNavigationTitle(SettingsSection.systemFeatures.title)
    #if os(iOS) || os(macOS)
      .animation(.appCurve(0.2), value: enableSpotlightIndexing)
      .animation(.appCurve(0.2), value: enableSpotlightBookIndexing)
      .animation(.appCurve(0.2), value: enableSpotlightSeriesIndexing)
      .animation(.appCurve(0.2), value: indexAllLibraries)
      .task {
        await loadLibrariesAndSelection()
      }
      .onChange(of: enableSpotlightIndexing) { _, newValue in
        if newValue {
          rebuildSpotlightIndex()
        } else {
          SpotlightIndexService.removeAllItems()
        }
      }
      .onChange(of: enableSpotlightBookIndexing) { _, _ in
        rebuildSpotlightIndex()
      }
      .onChange(of: enableSpotlightSeriesIndexing) { _, _ in
        rebuildSpotlightIndex()
      }
    #endif
  }

  #if os(iOS) || os(macOS)
    private func loadLibrariesAndSelection() async {
      let instanceId = currentInstanceId
      guard !instanceId.isEmpty else {
        libraries = []
        indexedLibraryIds = []
        indexAllLibraries = true
        return
      }

      await LibraryManager.shared.loadLibraries()
      let loadedLibraries =
        (try? await DatabaseOperator.database().fetchLibraries(instanceId: instanceId))
        ?? []
        .filter { $0.id != KomgaLibrary.allLibrariesId }
      libraries = loadedLibraries

      let validLibraryIds = Set(loadedLibraries.map(\.id))
      if let selectedLibraryIds = AppConfig.spotlightIndexedLibraryIds(instanceId: instanceId) {
        indexAllLibraries = false
        indexedLibraryIds = Set(selectedLibraryIds.filter { validLibraryIds.contains($0) })
        if selectedLibraryIds.count != indexedLibraryIds.count {
          persistSelection()
        }
      } else {
        indexAllLibraries = true
        indexedLibraryIds = validLibraryIds
      }
    }

    private func toggleLibrary(_ libraryId: String) {
      if indexedLibraryIds.contains(libraryId) {
        indexedLibraryIds.remove(libraryId)
      } else {
        indexedLibraryIds.insert(libraryId)
      }
      persistSelection()
    }

    private func persistSelection() {
      let instanceId = currentInstanceId
      guard !instanceId.isEmpty else { return }

      if indexAllLibraries {
        AppConfig.clearSpotlightLibrarySelection(instanceId: instanceId)
      } else {
        AppConfig.setSpotlightIndexedLibraryIds(
          Array(indexedLibraryIds).sorted(),
          instanceId: instanceId
        )
      }
      rebuildSpotlightIndex()
    }

    private func rebuildSpotlightIndex() {
      guard !currentInstanceId.isEmpty else { return }
      SpotlightIndexService.removeAllItems()
      if enableSpotlightIndexing {
        SpotlightIndexService.indexAllDownloadedBooks(instanceId: currentInstanceId)
      }
    }
  #endif
}
