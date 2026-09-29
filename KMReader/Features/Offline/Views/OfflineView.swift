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
  @AppStorage("isOffline") private var isOffline: Bool = false

  @State private var seriesViewModel = SeriesViewModel()
  @State private var bookViewModel = BookViewModel()
  @State private var refreshTrigger = UUID()
  @State private var searchQuery: String = ""
  @State private var activeSearchText: String = ""
  #if os(iOS) || os(macOS)
    @State private var showLibraryPicker = false
    @State private var scopeLibraries: [SidebarLibraryItem] = []
  #endif
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false
  @State private var showSyncConfirmation = false
  @State private var latestReadHistoryTime: Date?
  @State private var syncInfo: OfflineInstanceSyncInfo?

  private var syncViewModel: SyncViewModel {
    SyncViewModel.shared
  }

  private var coverSyncViewModel: OfflineCoverSyncViewModel {
    OfflineCoverSyncViewModel.shared
  }

  private var lastSyncTimeText: String {
    guard let syncInfo else {
      return String(localized: "settings.sync_data.never")
    }
    if syncInfo.latestSync == Date(timeIntervalSince1970: 0) {
      return String(localized: "settings.sync_data.never")
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: syncInfo.latestSync, relativeTo: Date())
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
    return dashboard.libraryIds
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

        VStack(spacing: 12) {
          syncCard
          downloadShortcuts
        }
        .padding(.horizontal)
        .padding(.top, librarySelection == nil ? 12 : 0)
        .padding(.bottom, 12)

        HStack {
          Spacer()
          Picker("", selection: offlineContentBinding) {
            Text(String(localized: "browse.content.series")).tag(BrowseContentType.series)
            Text(String(localized: "browse.content.books")).tag(BrowseContentType.books)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)

        browseContentView
      }
    }
    .platformNavigationTitle(title)
    .searchable(text: $searchQuery, placement: searchPlacement)
    #if os(iOS) || os(macOS)
      .refreshableWithMinimumHold {
        await refreshOfflinePage()
      }
      .task(id: current.instanceId) {
        await refreshScopeLibraries()
      }
      .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) { notification in
        guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
        Task {
          await loadScopeLibraries()
        }
      }
      .toolbar {
        if librarySelection == nil {
          #if os(macOS)
            ToolbarItem(placement: .navigation) {
              LibraryScopeToolbarButton(libraries: scopeLibraries, isPresented: $showLibraryPicker)
            }
          #else
            ToolbarItem(placement: .cancellationAction) {
              LibraryScopeToolbarButton(libraries: scopeLibraries, isPresented: $showLibraryPicker)
            }
          #endif
        }

        ToolbarItemGroup(placement: .confirmationAction) {
          Button {
            showSavedFilters = true
          } label: {
            Image(systemName: "bookmark")
          }
          .accessibilityLabel(String(localized: "Saved Filters"))

          Button {
            showFilterSheet = true
          } label: {
            Image(systemName: "line.3.horizontal.decrease")
          }
          .accessibilityLabel(String(localized: "Filter"))
        }
      }
      .sheet(isPresented: $showLibraryPicker) {
        LibraryPickerSheet()
      }
      .sheet(isPresented: $showSavedFilters) {
        SavedFiltersView(filterType: savedFilterType)
      }
    #endif
    .alert(
      String(localized: "offline.sync.confirm.title"),
      isPresented: $showSyncConfirmation
    ) {
      Button(String(localized: "offline.sync.confirm.action")) {
        Task {
          await syncViewModel.syncData()
          await loadSyncInfo()
        }
      }
      Button(String(localized: "offline.sync.confirm.forceAction"), role: .destructive) {
        Task {
          await syncViewModel.syncData(forceFullSync: true)
          await loadSyncInfo()
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(String(localized: "offline.sync.confirm.message"))
    }
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
    .task(id: current.instanceId) {
      guard !authViewModel.isSwitching else { return }
      latestReadHistoryTime = AppConfig.recentlyReadRecordTime(instanceId: current.instanceId)
      await loadSyncInfo()
    }
    .onChange(of: resolvedLibraryIdsKey) { _, _ in
      guard !authViewModel.isSwitching else { return }
      refreshTrigger = UUID()
      Task {
        await loadSyncInfo()
      }
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

  private var syncCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        showSyncConfirmation = true
      } label: {
        HStack {
          Label(
            String(localized: "settings.sync_data"),
            systemImage: "arrow.triangle.2.circlepath"
          )
          Spacer()
          if syncViewModel.isSyncing {
            ProgressView()
          } else {
            Text(lastSyncTimeText)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
      .disabled(syncViewModel.isSyncing || isOffline)

      Text(String(localized: "settings.sync_data.description"))
        .font(.caption)
        .foregroundColor(.secondary)

      Divider()

      Button {
        triggerReadingProgressSync(force: true)
      } label: {
        HStack {
          Image(systemName: "book.circle")
            .imageScale(.small)
          Text(
            String(
              localized: "offline.sync.confirm.progressOnlyAction",
              defaultValue: "Sync Reading History"
            )
          )
          .font(.caption)
          Spacer()
          if let syncTime = latestReadHistoryTime {
            HStack(spacing: 4) {
              Text(
                String(
                  localized: "offline.sync.readHistory.lastRead",
                  defaultValue: "Last read"
                )
              )
              Text(syncTime.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                .monospacedDigit()
            }
            .font(.caption2)
            .foregroundColor(.secondary)
          } else {
            Text(String(localized: "settings.sync_data.never"))
              .font(.caption2)
              .foregroundColor(.secondary)
              .monospacedDigit()
          }
        }
      }
      .disabled(isOffline)

    }
    .padding(12)
    .background(.thinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private var downloadShortcuts: some View {
    VStack(spacing: 8) {
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
    }
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
    latestReadHistoryTime = AppConfig.recentlyReadRecordTime(instanceId: current.instanceId)
    await refreshBrowse()
    await loadSyncInfo()
  }

  #if os(iOS) || os(macOS)
    private func refreshScopeLibraries() async {
      do {
        let loaded = try await LibraryScopeLoader.refresh(instanceId: current.instanceId)
        if scopeLibraries != loaded {
          scopeLibraries = loaded
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }

    private func loadScopeLibraries() async {
      do {
        let loaded = try await LibraryScopeLoader.load(instanceId: current.instanceId)
        if scopeLibraries != loaded {
          scopeLibraries = loaded
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  #endif

  private func loadSyncInfo() async {
    guard !current.instanceId.isEmpty else {
      if syncInfo != nil { syncInfo = nil }
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedSyncInfo = try await database.fetchOfflineInstanceSyncInfo(
        instanceId: current.instanceId
      )
      if syncInfo != loadedSyncInfo {
        syncInfo = loadedSyncInfo
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func triggerReadingProgressSync(force: Bool = false) {
    guard !isOffline, !current.instanceId.isEmpty else { return }

    Task(priority: .utility) {
      await syncViewModel.syncReadingProgressOnly(force: force)
      await MainActor.run {
        latestReadHistoryTime = AppConfig.recentlyReadRecordTime(instanceId: current.instanceId)
      }
    }
  }
}
