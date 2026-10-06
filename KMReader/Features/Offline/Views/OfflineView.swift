//
// OfflineView.swift
//
//

import SwiftUI

struct OfflineView: View {
  let authViewModel: AuthViewModel
  @Environment(\.browseLibrarySelection) private var librarySelection

  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("offlineBrowseContent") private var offlineBrowseContent: BrowseContentType = .series
  @AppStorage("seriesBrowseLayout") private var seriesBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("bookBrowseLayout") private var bookBrowseLayout: BrowseLayoutMode = .grid
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var seriesViewModel = SeriesViewModel()
  @State private var bookViewModel = BookViewModel()
  @State private var refreshTrigger = UUID()
  @State private var searchQuery: String = ""
  @State private var activeSearchText: String = ""
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false
  @State private var scope: LibraryBrowseScope = .pinned
  @State private var shortcutsWidth: CGFloat = PlatformHelper.isPad ? .infinity : 0
  #if os(iOS) || os(macOS)
    @State private var showLibraryPicker = false
    @State private var scopeStore = LibraryScopeStore()
    @State private var downloadStats: (count: Int, sizeBytes: Int64)?
    @State private var progressTracker = DownloadProgressTracker.shared
  #endif

  private var coverSyncViewModel: OfflineCoverSyncViewModel {
    OfflineCoverSyncViewModel.shared
  }

  private var title: String {
    if let library = librarySelection {
      return library.name
    }
    return String(localized: "tab.offline")
  }

  private var resolvedLibraryIds: [String] {
    if let library = librarySelection {
      return [library.libraryId]
    }
    return scope.resolvedIds(pinned: dashboard.libraryIds)
  }

  private var resolvedLibraryIdsKey: String {
    resolvedLibraryIds.joined(separator: ",")
  }

  private var resolvedOfflineContent: BrowseContentType {
    switch offlineBrowseContent {
    case .series, .books:
      return offlineBrowseContent
    case .collections, .readlists:
      return .series
    }
  }

  private var offlineContentBinding: Binding<BrowseContentType> {
    Binding(
      get: { resolvedOfflineContent },
      set: { newValue in
        offlineBrowseContent = newValue == .books ? .books : .series
      }
    )
  }

  private var savedFilterType: SavedFilterType {
    resolvedOfflineContent == .books ? .books : .series
  }

  private var browseLayoutBinding: Binding<BrowseLayoutMode> {
    resolvedOfflineContent == .books ? $bookBrowseLayout : $seriesBrowseLayout
  }

  #if os(iOS) || os(macOS)
    /// Facts line for the scope caption: total downloaded size first, then the
    /// downloaded-books count.
    private var downloadFactsText: Text? {
      guard let downloadStats, downloadStats.count > 0 else { return nil }
      var parts: [Text] = []
      if downloadStats.sizeBytes > 0 {
        parts.append(Text(Double(downloadStats.sizeBytes).humanReadableFileSize))
      }
      parts.append(
        Text(
          String.localizedStringWithFormat(
            String(localized: "library.list.metrics.books", defaultValue: "%lld books"),
            downloadStats.count)))
      return LibraryMetricsText.join(parts, separator: " · ")
    }

    private var chipCaptionText: Text {
      LibraryMetricsText.scopeCaption(title: scopeCaptionTitle, facts: downloadFactsText)
    }

    private var scopeCaptionTitle: String {
      if let selection = librarySelection {
        return selection.name
      }
      return scope.title(pinnedIds: dashboard.libraryIds, libraries: scopeStore.libraries)
        ?? String(localized: "All Libraries")
    }
  #endif

  /// Pins the search bar only on iPhone: there it renders as a drawer row whose
  /// hide/reveal animation fights the refresh control during pull-to-refresh.
  /// iPad and macOS keep the search field in the toolbar, which never conflicts.
  private var searchPlacement: SearchFieldPlacement {
    #if os(iOS)
      return PlatformHelper.isPad ? .automatic : .navigationBarDrawer(displayMode: .always)
    #else
      return .automatic
    #endif
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        #if !os(iOS) && !os(macOS)
          if let library = librarySelection {
            VStack(alignment: .leading) {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: ContentIcon.library)
                Text(library.name)
                  .font(.title2)
                if let fileSize = library.fileSize {
                  Text(fileSize.humanReadableFileSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                Spacer()
              }
            }
            .padding()
          }
        #endif

        downloadShortcuts
          .padding(.horizontal)
          .padding(.top, librarySelection == nil ? 12 : 0)
          .padding(.bottom, 12)

        HStack {
          BrowseContentTypeMenu(
            selection: offlineContentBinding,
            types: [.series, .books],
            counts: [:]
          )
          #if os(iOS) || os(macOS)
            chipCaptionText
              .font(.caption)
              .lineLimit(1)
              .truncationMode(.tail)
          #endif
          Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)

        browseContentView
      }
      .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { shortcutsWidth = $0 }
    }
    .inlineLargeBarTitleStyle(enabled: librarySelection == nil)
    .platformNavigationTitle(title)
    .searchable(text: $searchQuery, placement: searchPlacement)
    #if os(iOS) || os(macOS)
      .refreshableWithMinimumHold {
        await refreshOfflinePage()
      }
      .task(id: current.instanceId) {
        await scopeStore.refresh(instanceId: current.instanceId)
      }
      .task(id: "\(current.instanceId)|\(resolvedLibraryIdsKey)") {
        await loadDownloadStats()
      }
      .onChange(of: progressTracker.queueUpdateToken) { _, _ in
        Task { await loadDownloadStats() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) { notification in
        guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
        Task {
          await scopeStore.load(instanceId: current.instanceId)
        }
      }
      .onChange(of: scopeStore.libraries) { _, libraries in
        // A scoped library that vanished falls back to the aggregate.
        guard !libraries.isEmpty,
          let scopedId = scope.libraryId,
          !libraries.contains(where: { $0.libraryId == scopedId })
        else { return }
        scope = .pinned
      }
      .onChange(of: dashboard.libraryIds) { _, pinnedIds in
        // The Pinned item only exists while pins do; an emptied pinned set
        // is the full set, which All already represents.
        if pinnedIds.isEmpty, scope == .pinned {
          scope = .all
        }
      }
      .toolbar {
        #if os(iOS)
          if librarySelection == nil && !PlatformHelper.isPad, #available(iOS 26.0, *) {
            ToolbarItem(placement: .largeTitle) {
              InlineLargeBarTitle(title: title)
            }
          }
        #endif
        #if os(macOS)
          if librarySelection == nil {
            ToolbarItem(placement: .navigation) {
              LibraryScopeMenu(
                libraries: scopeStore.libraries,
                showLibraryPicker: $showLibraryPicker,
                scope: $scope)
            }
          }
        #endif
        #if os(iOS)
          if librarySelection == nil {
            if PlatformHelper.isPad {
              ToolbarItem(placement: .cancellationAction) {
                LibraryScopeMenu(
                  libraries: scopeStore.libraries,
                  showLibraryPicker: $showLibraryPicker,
                  scope: $scope)
              }
            } else {
              ToolbarItem(placement: .confirmationAction) {
                LibraryScopeMenu(
                  libraries: scopeStore.libraries,
                  showLibraryPicker: $showLibraryPicker,
                  scope: $scope)
              }
              if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .confirmationAction)
              }
            }
          }
        #endif
        ToolbarItem(placement: .confirmationAction) {
          BrowseActionsMenu(
            layoutMode: browseLayoutBinding,
            showsPresets: true,
            isFilterEnabled: true,
            onShowPresets: { showSavedFilters = true },
            onShowFilter: { showFilterSheet = true }
          )
        }
      }
      .sheet(isPresented: $showLibraryPicker) {
        LibraryPickerSheet()
      }
      .sheet(isPresented: $showSavedFilters) {
        SavedFiltersView(filterType: savedFilterType)
      }
    #endif
    .onSubmit(of: .search) {
      activeSearchText = searchQuery
    }
    .onChange(of: searchQuery) { _, newValue in
      if newValue.isEmpty {
        activeSearchText = ""
      }
    }
    .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
      if newValue {
        coverSyncViewModel.cancelSync()
        return
      }

      guard librarySelection == nil else { return }
      if oldValue && !newValue {
        refreshTrigger = UUID()
      }
    }
    .onChange(of: current.instanceId) { _, newValue in
      coverSyncViewModel.cancelSyncIfContextChanged(instanceId: newValue, isOffline: isOffline)
    }
    .onChange(of: isOffline) { _, newValue in
      coverSyncViewModel.cancelSyncIfContextChanged(
        instanceId: current.instanceId,
        isOffline: newValue
      )
    }
    .onChange(of: resolvedLibraryIdsKey) { _, _ in
      guard !authViewModel.isSwitching else { return }
      refreshTrigger = UUID()
    }
  }

  @ViewBuilder
  private var browseContentView: some View {
    switch resolvedOfflineContent {
    case .series, .collections, .readlists:
      OfflineSeriesBrowseView(
        libraryIds: resolvedLibraryIds,
        searchText: activeSearchText,
        refreshTrigger: refreshTrigger,
        viewModel: seriesViewModel,
        showFilterSheet: $showFilterSheet,
        showSavedFilters: $showSavedFilters
      )
    case .books:
      OfflineBooksBrowseView(
        libraryIds: resolvedLibraryIds,
        searchText: activeSearchText,
        refreshTrigger: refreshTrigger,
        viewModel: bookViewModel,
        showFilterSheet: $showFilterSheet,
        showSavedFilters: $showSavedFilters
      )
    }
  }

  private let shortcutsWideLayoutMinimumWidth: CGFloat = 640

  private var shortcutsSideBySide: Bool {
    shortcutsWidth >= shortcutsWideLayoutMinimumWidth
  }

  @ViewBuilder
  private var downloadShortcuts: some View {
    if shortcutsSideBySide {
      HStack(spacing: 8) {
        tasksShortcut
        booksShortcut
      }
    } else {
      VStack(spacing: 8) {
        tasksShortcut
        booksShortcut
      }
    }
  }

  private var tasksShortcut: some View {
    NavigationLink(value: NavDestination.settingsOfflineTasks) {
      OfflineShortcutRow(
        title: OfflineSection.tasks.title,
        subtitle: String(localized: "offline.shortcuts.tasks.subtitle"),
        systemImage: OfflineSection.tasks.icon,
        color: OfflineSection.tasks.color
      ) {
        OfflineTasksStatusView()
      }
    }
    .adaptiveButtonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  private var booksShortcut: some View {
    NavigationLink(value: NavDestination.settingsOfflineBooks) {
      OfflineShortcutRow(
        title: OfflineSection.books.title,
        subtitle: String(localized: "offline.shortcuts.books.subtitle"),
        systemImage: OfflineSection.books.icon,
        color: OfflineSection.books.color
      ) {
        OfflineBooksCountView()
      }
    }
    .adaptiveButtonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  private func refreshBrowse() async {
    switch resolvedOfflineContent {
    case .books:
      await bookViewModel.refreshBrowse()
    case .series, .collections, .readlists:
      await seriesViewModel.refreshBrowse()
    }
  }

  private func refreshOfflinePage() async {
    guard !authViewModel.isSwitching else { return }
    await refreshBrowse()
  }

  #if os(iOS) || os(macOS)
    private func loadDownloadStats() async {
      let instanceId = current.instanceId
      let libraryIds = resolvedLibraryIds
      guard !instanceId.isEmpty else {
        downloadStats = nil
        return
      }
      downloadStats =
        (try? await DatabaseOperator.database().fetchDownloadedBooksStats(
          instanceId: instanceId, libraryIds: libraryIds)) ?? (0, 0)
    }
  #endif
}
