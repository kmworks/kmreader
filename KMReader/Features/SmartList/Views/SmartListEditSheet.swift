//
// SmartListEditSheet.swift
//
//

import SwiftUI

struct SmartListEditSheet: View {
  enum Mode {
    case create
    case edit(SmartList)
  }

  let mode: Mode

  @AppStorage("currentAccount") private var current: Current = .init()
  @Environment(\.dismiss) private var dismiss

  @State private var name: String = ""
  @State private var summary: String = ""
  @State private var target: SmartList.Target = .book
  @State private var fullTextSearch: String = ""
  @State private var selectedLibraryIds: Set<String> = []
  @State private var bookBrowseOpts: BookBrowseOptions = BookBrowseOptions()
  @State private var seriesBrowseOpts: SeriesBrowseOptions = SeriesBrowseOptions()
  @State private var libraries: [LibraryInfo] = []
  @State private var visibility: SmartList.Visibility = .private
  @State private var shareTargets: [SmartListShareTarget] = []
  @State private var shareTargetsLoaded = false
  @State private var shareTargetsFailed = false
  @State private var selectedShareUserIds: Set<String> = []
  @State private var lossyFilter = false
  @State private var showLibraryPicker = false
  @State private var showFilterSheet = false
  @State private var isSaving = false
  /// Edit-mode baseline for the filter subsection; `search` is only sent when
  /// the current state differs from it, so reverting an edit by hand never
  /// rewrites the stored document.
  private let initialFullTextSearch: String
  private let initialLibraryIds: Set<String>
  private let initialBookBrowseOpts: BookBrowseOptions
  private let initialSeriesBrowseOpts: SeriesBrowseOptions

  init(mode: Mode) {
    self.mode = mode
    let lossy: Bool
    switch mode {
    case .create:
      initialFullTextSearch = ""
      initialLibraryIds = []
      initialBookBrowseOpts = BookBrowseOptions()
      initialSeriesBrowseOpts = SeriesBrowseOptions()
      lossy = false
    case .edit(let smartList):
      switch smartList.target {
      case .book:
        let state = SmartListFilterMapper.bookFilterState(from: smartList.search)
        initialFullTextSearch = state.fullTextSearch
        initialLibraryIds = Set(state.libraryIds)
        initialBookBrowseOpts = state.browseOpts
        initialSeriesBrowseOpts = SeriesBrowseOptions()
        lossy = state.lossy
      case .series:
        let state = SmartListFilterMapper.seriesFilterState(from: smartList.search)
        initialFullTextSearch = state.fullTextSearch
        initialLibraryIds = Set(state.libraryIds)
        initialBookBrowseOpts = BookBrowseOptions()
        initialSeriesBrowseOpts = state.browseOpts
        lossy = state.lossy
      }
    }
    _lossyFilter = State(initialValue: lossy)
    guard case .edit(let smartList) = mode else { return }
    _name = State(initialValue: smartList.name)
    _summary = State(initialValue: smartList.summary)
    _target = State(initialValue: smartList.target)
    _visibility = State(initialValue: smartList.visibility)
    _selectedShareUserIds = State(initialValue: Set(smartList.sharedWithUserIds))
    switch smartList.target {
    case .book:
      _selectedLibraryIds = State(initialValue: initialLibraryIds)
      _bookBrowseOpts = State(initialValue: initialBookBrowseOpts)
      _fullTextSearch = State(initialValue: initialFullTextSearch)
    case .series:
      _selectedLibraryIds = State(initialValue: initialLibraryIds)
      _seriesBrowseOpts = State(initialValue: initialSeriesBrowseOpts)
      _fullTextSearch = State(initialValue: initialFullTextSearch)
    }
  }

  private var filtersModified: Bool {
    fullTextSearch != initialFullTextSearch
      || selectedLibraryIds != initialLibraryIds
      || bookBrowseOpts != initialBookBrowseOpts
      || seriesBrowseOpts != initialSeriesBrowseOpts
  }

  private var isCreating: Bool {
    if case .create = mode { return true }
    return false
  }

  private var sheetTitle: String {
    isCreating
      ? String(localized: "smartlist.create.title", defaultValue: "New Smart List")
      : String(localized: "smartlist.edit.title", defaultValue: "Edit Smart List")
  }

  private var canSave: Bool {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    // The server rejects a SHARED list without share targets.
    if current.isAdmin && visibility == .shared && selectedShareUserIds.isEmpty { return false }
    return true
  }

  private var librariesSummary: String {
    if selectedLibraryIds.isEmpty {
      return String(localized: "All Libraries")
    }
    return String.localizedStringWithFormat(
      String(localized: "library.scope.librariesCount", defaultValue: "%lld Libraries"),
      selectedLibraryIds.count)
  }

  private var filterSummary: String {
    let count = activeFilterCount
    if count == 0 {
      return String(
        localized: "smartlist.filters.none", defaultValue: "No filters — matches everything")
    }
    return String.localizedStringWithFormat(
      String(localized: "smartlist.filters.activeCount", defaultValue: "%lld filters active"),
      count)
  }

  /// Per-value granularity like kmweb's activeFilterCount; each active
  /// tri-state flag counts once. Only the metadata kinds the target's search
  /// filters support are counted.
  private var activeFilterCount: Int {
    switch target {
    case .book:
      return bookBrowseOpts.includeReadStatuses.count
        + bookBrowseOpts.excludeReadStatuses.count
        + (bookBrowseOpts.oneshotFilter.isActive ? 1 : 0)
        + (bookBrowseOpts.deletedFilter.isActive ? 1 : 0)
        + metadataValueCount(bookBrowseOpts.metadataFilter, seriesKinds: false)
    case .series:
      return seriesBrowseOpts.includeReadStatuses.count
        + seriesBrowseOpts.excludeReadStatuses.count
        + seriesBrowseOpts.includeSeriesStatuses.count
        + seriesBrowseOpts.excludeSeriesStatuses.count
        + (seriesBrowseOpts.completeFilter.isActive ? 1 : 0)
        + (seriesBrowseOpts.oneshotFilter.isActive ? 1 : 0)
        + (seriesBrowseOpts.deletedFilter.isActive ? 1 : 0)
        + metadataValueCount(seriesBrowseOpts.metadataFilter, seriesKinds: true)
    }
  }

  var body: some View {
    SheetView(title: sheetTitle, size: .large, applyFormStyle: true) {
      Form {
        Section {
          TextField(
            String(localized: "smartlist.name", defaultValue: "Smart List Name"), text: $name)
          TextField(String(localized: "Summary (Optional)"), text: $summary, axis: .vertical)
            .lineLimit(3...6)
        }

        // The server only accepts target and search together, so an existing
        // list's target is fixed.
        if isCreating {
          Section(String(localized: "smartlist.target", defaultValue: "Target")) {
            Picker(
              String(localized: "smartlist.target", defaultValue: "Target"), selection: $target
            ) {
              Text(String(localized: "browse.content.books")).tag(SmartList.Target.book)
              Text(String(localized: "browse.content.series")).tag(SmartList.Target.series)
            }
            .pickerStyle(.segmented)
          }
        }

        Section(String(localized: "Filters")) {
          TextField(
            String(localized: "smartlist.filters.searchText", defaultValue: "Search text"),
            text: $fullTextSearch
          )

          Button {
            showLibraryPicker = true
          } label: {
            HStack {
              Text(String(localized: "Libraries"))
              Spacer()
              Text(librariesSummary)
                .foregroundStyle(.secondary)
            }
          }

          Button {
            showFilterSheet = true
          } label: {
            HStack {
              Text(String(localized: "Filter"))
              Spacer()
              Text(filterSummary)
                .foregroundStyle(.secondary)
            }
          }

          if lossyFilter {
            Label(
              String(
                localized: "smartlist.lossyWarning",
                defaultValue:
                  "The stored filter contains conditions the app cannot edit. Changing any filter replaces the whole stored filter."
              ),
              systemImage: AppIcon.loadError
            )
            .foregroundStyle(.secondary)
          }
        }

        if current.isAdmin {
          Section(String(localized: "smartlist.visibility", defaultValue: "Visibility")) {
            Picker(
              String(localized: "smartlist.visibility", defaultValue: "Visibility"),
              selection: $visibility
            ) {
              ForEach(SmartList.Visibility.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
              }
            }
            .pickerStyle(.segmented)

            if visibility == .shared {
              if shareTargetsFailed {
                Button(String(localized: "Retry")) {
                  Task {
                    await loadShareTargets()
                  }
                }
                .adaptiveButtonStyle(.bordered)
              } else if !shareTargetsLoaded {
                LoadingIcon()
                  .frame(maxWidth: .infinity)
              } else if shareTargets.isEmpty {
                Text(
                  String(
                    localized: "smartlist.sharedWith.empty",
                    defaultValue: "No other users on this server.")
                )
                .foregroundStyle(.secondary)
              } else {
                ForEach(shareTargets) { shareTarget in
                  Button {
                    toggleShareTarget(shareTarget.id)
                  } label: {
                    HStack {
                      Text(shareTarget.email)
                      Spacer()
                      if selectedShareUserIds.contains(shareTarget.id) {
                        Image(systemName: AppIcon.confirm)
                          .foregroundStyle(.tint)
                      }
                    }
                    .foregroundStyle(.primary)
                    .animation(.appCurve(), value: selectedShareUserIds.contains(shareTarget.id))
                  }
                }
              }
            }
          }
        }
      }
    } controls: {
      Button(action: save) {
        if isSaving {
          LoadingIcon()
        } else {
          Label(
            isCreating ? String(localized: "Create") : String(localized: "Save"),
            systemImage: AppIcon.confirm)
        }
      }
      .disabled(!canSave || isSaving)
    }
    .task {
      await loadLibraries()
      if current.isAdmin {
        await loadShareTargets()
      }
    }
    .sheet(isPresented: $showLibraryPicker) {
      SmartListLibraryPickerSheet(libraries: libraries, selection: $selectedLibraryIds)
    }
    .sheet(isPresented: $showFilterSheet) {
      switch target {
      case .book:
        BookBrowseOptionsSheet(
          browseOpts: $bookBrowseOpts,
          libraryIds: selectedLibraryIds.isEmpty ? nil : selectedLibraryIds.sorted(),
          showsSort: false
        )
      case .series:
        SeriesBrowseOptionsSheet(
          browseOpts: $seriesBrowseOpts,
          libraryIds: selectedLibraryIds.isEmpty ? nil : selectedLibraryIds.sorted(),
          showsSort: false
        )
      }
    }
    .onChange(of: target) { _, _ in
      bookBrowseOpts = BookBrowseOptions()
      seriesBrowseOpts = SeriesBrowseOptions()
    }
  }

  private func metadataValueCount(_ config: MetadataFilterConfig, seriesKinds: Bool) -> Int {
    var values: [[String]?] = [config.authors, config.tags]
    if seriesKinds {
      values += [
        config.publishers, config.genres, config.languages, config.ageRatings,
        config.releaseYears,
      ]
    }
    return values.reduce(0) { $0 + ($1?.count ?? 0) }
  }

  private func toggleShareTarget(_ id: String) {
    if selectedShareUserIds.contains(id) {
      selectedShareUserIds.remove(id)
    } else {
      selectedShareUserIds.insert(id)
    }
  }

  private func loadLibraries() async {
    let loaded =
      (try? await DatabaseOperator.database().fetchLibraries(instanceId: current.instanceId))
      ?? []
    libraries = loaded.filter { $0.id != KomgaLibrary.allLibrariesId }
  }

  private func loadShareTargets() async {
    shareTargetsFailed = false
    do {
      shareTargets = try await SmartListService.getShareTargets()
      shareTargetsLoaded = true
    } catch {
      shareTargetsFailed = true
      ErrorManager.shared.alert(error: error)
    }
  }

  private func buildSearchDocument() throws -> [String: Any] {
    let data: Data
    switch target {
    case .book:
      data = try JSONEncoder().encode(
        SmartListFilterMapper.bookSearch(
          libraryIds: selectedLibraryIds.sorted(),
          browseOpts: bookBrowseOpts,
          fullTextSearch: fullTextSearch))
    case .series:
      data = try JSONEncoder().encode(
        SmartListFilterMapper.seriesSearch(
          libraryIds: selectedLibraryIds.sorted(),
          browseOpts: seriesBrowseOpts,
          fullTextSearch: fullTextSearch))
    }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  }

  private func save() {
    withAnimation {
      isSaving = true
    }

    // Share targets are only meaningful for SHARED lists; anything else omits
    // the field so the server keeps or ignores the stored ids.
    let sharedWithUserIds: [String]? =
      current.isAdmin && visibility == .shared ? selectedShareUserIds.sorted() : nil
    let visibilityPayload: SmartList.Visibility? = current.isAdmin ? visibility : nil

    Task {
      do {
        switch mode {
        case .create:
          _ = try await SmartListService.createSmartList(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            target: target,
            visibility: visibilityPayload,
            sharedWithUserIds: sharedWithUserIds,
            search: buildSearchDocument()
          )
          ErrorManager.shared.notify(
            message: String(
              localized: "notification.smartList.created", defaultValue: "Smart list created"))
        case .edit(let smartList):
          try await SmartListService.updateSmartList(
            smartListId: smartList.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            visibility: visibilityPayload,
            sharedWithUserIds: sharedWithUserIds,
            search: filtersModified ? buildSearchDocument() : nil
          )
          ErrorManager.shared.notify(
            message: String(
              localized: "notification.smartList.updated", defaultValue: "Smart list updated"))
        }
        dismiss()
      } catch {
        withAnimation {
          isSaving = false
        }
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
