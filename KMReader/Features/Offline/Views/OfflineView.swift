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
  #if os(iOS) || os(macOS)
    @State private var showLibraryPicker = false
    @State private var scopeStore = LibraryScopeStore()
  #endif
  @State private var showFilterSheet = false
  @State private var showSavedFilters = false

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

  private var browseLayoutBinding: Binding<BrowseLayoutMode> {
    resolvedOfflineContent == .books ? $bookBrowseLayout : $seriesBrowseLayout
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

        downloadShortcuts
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
        await scopeStore.refresh(instanceId: current.instanceId)
      }
      .onReceive(NotificationCenter.default.publisher(for: .sidebarProjectionDidChange)) { notification in
        guard notification.userInfo?["instanceId"] as? String == current.instanceId else { return }
        Task {
          await scopeStore.load(instanceId: current.instanceId)
        }
      }
      .toolbar {
        if librarySelection == nil {
          #if os(macOS)
            ToolbarItem(placement: .navigation) {
              LibraryScopeToolbarButton(libraries: scopeStore.libraries, isPresented: $showLibraryPicker)
            }
          #else
            ToolbarItem(placement: .cancellationAction) {
              LibraryScopeToolbarButton(libraries: scopeStore.libraries, isPresented: $showLibraryPicker)
            }
          #endif
        }
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
    await refreshBrowse()
  }
}
