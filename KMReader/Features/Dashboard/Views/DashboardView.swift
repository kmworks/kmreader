//
// DashboardView.swift
//
//

import SwiftUI

struct DashboardView: View {
  let authViewModel: AuthViewModel
  let readerPresentation: ReaderPresentationManager

  @State private var isRefreshing = false
  @State private var showLibraryPicker = false
  @State private var showLibraryAddSheet = false
  @State private var isCheckingConnection = false
  @State private var scopeStore = LibraryScopeStore()
  @State private var dashboardScopeStore = DashboardLibraryScopeStore.shared
  @State private var searchQuery = ""
  // Results re-query only on submit, so the submitted text is stored apart
  // from the live field text.
  @State private var submittedSearchText = ""
  @State private var isSearchPresented = false

  @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("enableSSEAutoRefresh") private var enableSSEAutoRefresh: Bool = true
  @AppStorage("enableSSE") private var enableSSE: Bool = true
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("readListContinuationEnabled") private var readListContinuationEnabled: Bool = false

  private let sseService = SSEService.shared
  private let logger = AppLogger(.dashboard)

  private var showsEmptyLibraryGuidance: Bool {
    scopeStore.hasLoaded && scopeStore.libraries.isEmpty && !isOffline
  }

  private var showsDashboardSearchField: Bool {
    // iPhone has a search tab instead; tvOS search lives on the browse page.
    #if os(macOS)
      return true
    #elseif os(iOS)
      return PlatformHelper.isPad
    #else
      return false
    #endif
  }

  /// Header content for the active scope: All and Pinned aggregate the covered
  /// libraries' metrics; a single library shows its own name and metrics.
  private var scopedLibraryHeader: some View {
    LibraryScopeHeader(
      scope: DashboardLibraryScopeStore.shared.scope,
      pinnedIds: dashboard.libraryIds,
      libraries: scopeStore.libraries,
      allLibrariesEntry: scopeStore.allLibrariesEntry)
  }

  @ViewBuilder
  private var dashboardHeader: some View {
    #if os(tvOS)
      HStack {
        Button {
          showLibraryPicker = true
        } label: {
          Label(String(localized: "Libraries"), systemImage: ContentIcon.library)
        }

        NavigationLink(value: NavDestination.settingsReadingStats) {
          Label(
            ServerSection.readingStats.title,
            systemImage: ServerSection.readingStats.icon
          )
        }

        if enableSSE {
          if isOffline {
            Button {
              Task {
                await tryReconnect()
              }
            } label: {
              if isCheckingConnection {
                LoadingIcon()
              } else {
                Label(String(localized: "settings.offline"), systemImage: "wifi.slash")
                  .foregroundStyle(.orange)
              }
            }
            .disabled(isCheckingConnection)
          } else {
            Button {
              Task {
                await refreshDashboard(reason: "Manual tvOS button")
              }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
          }
        }
        Spacer()
      }
      .padding()
    #endif
  }

  @MainActor
  private func refreshDashboard(reason: String, showsToolbarIndicator: Bool = true) async {
    logger.debug("Dashboard refresh requested: \(reason)")

    // Check SSE connection status and reconnect if disconnected
    if enableSSE {
      await SSEService.shared.connect()
    }

    if showsToolbarIndicator {
      withAnimation {
        isRefreshing = true
      }
    }
    await scopeStore.refreshMetrics(instanceId: current.instanceId)
    await DashboardSectionRefreshNotifier.postAll(source: .manual, reason: reason)
    if showsToolbarIndicator {
      withAnimation {
        isRefreshing = false
      }
    }
  }

  private func handleSSEEvent(_ info: SSEEventInfo) {
    switch info.type {
    case .libraryAdded, .libraryChanged, .libraryDeleted:
      Task {
        await DashboardSectionRefreshNotifier.postAll(
          source: .auto,
          reason: "SSE \(info.type.rawValue)"
        )
      }
    default:
      break
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        dashboardHeader

        #if os(iOS) || os(macOS)
          scopedLibraryHeader
        #endif

        if showsEmptyLibraryGuidance {
          DashboardEmptyLibraryView(isAdmin: current.isAdmin) {
            showLibraryAddSheet = true
          }
        } else {
          ForEach(dashboard.sections, id: \.id) { section in
            if section == .readListsInProgress {
              if readListContinuationEnabled {
                ReadListsInProgressSectionView(section: section)
              }
            } else if section.isLocalSection {
              DashboardPinnedSectionView(section: section)
            } else {
              DashboardSectionView(section: section)
            }
          }
        }
      }
    }
    .inlineLargeBarTitleStyle()
    .platformNavigationTitle(String(localized: "title.dashboard"))
    .overlay {
      // The dashboard stays mounted underneath, so cancelling a search never
      // reloads sections. The overlay appears only once a query is submitted —
      // while typing or after clearing, the dashboard stays visible.
      if showsDashboardSearchField && isSearchPresented && !submittedSearchText.isEmpty {
        DashboardSearchResultsView(searchText: submittedSearchText)
      }
    }
    #if os(iOS) || os(macOS)
      .searchableIfNeeded(
        text: $searchQuery,
        isPresented: $isSearchPresented,
        enabled: showsDashboardSearchField
      )
      .onSubmit(of: .search) {
        submittedSearchText = searchQuery
      }
      .onChange(of: searchQuery) { _, newValue in
        // Clearing the field resets results immediately, like the standalone
        // search page; other edits still wait for submit.
        if newValue.isEmpty {
          submittedSearchText = ""
        }
      }
      .onChange(of: isSearchPresented) { _, presented in
        if !presented {
          searchQuery = ""
          submittedSearchText = ""
        }
      }
    #endif
    .onChange(of: authViewModel.isSwitching) { oldValue, newValue in
      // Refresh when server switch completes (transitions from switching to not switching)
      // This avoids race condition where refresh happens after logout but before new auth is ready
      if oldValue && !newValue {
        Task {
          await refreshDashboard(reason: "Server switch completed")
        }
      }
    }
    .onChange(of: dashboard.libraryIds) { _, _ in
      // Skip during server switch - dedicated refresh happens when switch completes
      guard !authViewModel.isSwitching else { return }
      // Bypass auto-refresh setting for configuration changes
      Task {
        await refreshDashboard(reason: "Library filter changed")
      }
      WidgetDataService.refreshWidgetData()
    }
    .onChange(of: DashboardLibraryScopeStore.shared.scope) { _, _ in
      // Widget data follows the pinned aggregate, not the session scope.
      guard !authViewModel.isSwitching else { return }
      Task {
        await refreshDashboard(reason: "Library scope changed")
      }
    }
    .onChange(of: scopeStore.libraries) { _, libraries in
      // A scoped library that vanished (deleted or never loaded) falls back
      // to the aggregate.
      guard !libraries.isEmpty,
        let scopedId = DashboardLibraryScopeStore.shared.scope.libraryId,
        !libraries.contains(where: { $0.libraryId == scopedId })
      else { return }
      DashboardLibraryScopeStore.shared.reset()
    }
    .task {
      DashboardRefreshCoordinator.shared.configure(
        autoRefreshEnabled: enableSSEAutoRefresh
      )
      if enableSSE && !isOffline {
        await SSEService.shared.connect()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .sseEventReceived)) { notification in
      guard let info = notification.userInfo?["info"] as? SSEEventInfo else { return }
      handleSSEEvent(info)
    }
    .onChange(of: enableSSEAutoRefresh) { _, newValue in
      DashboardRefreshCoordinator.shared.setAutoRefreshEnabled(newValue)
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
    .sheet(
      isPresented: $showLibraryAddSheet,
      onDismiss: {
        Task {
          await scopeStore.load(instanceId: current.instanceId)
        }
      }
    ) {
      LibraryAddSheet()
    }
    #if os(iOS) || os(macOS)
      .toolbar {
        #if os(iOS)
          if #available(iOS 26.0, *), !PlatformHelper.isPad {
            ToolbarItem(placement: .largeTitle) {
              InlineLargeBarTitle(title: String(localized: "title.dashboard"))
            }
          }
        #endif

        #if os(macOS)
          ToolbarItem(placement: .navigation) {
            LibraryScopeMenu(
              libraries: scopeStore.libraries,
              showLibraryPicker: $showLibraryPicker,
              scope: $dashboardScopeStore.scope)
          }
        #endif

        #if os(iOS)
          if PlatformHelper.isPad {
            ToolbarItem(placement: .cancellationAction) {
              LibraryScopeMenu(
                libraries: scopeStore.libraries,
                showLibraryPicker: $showLibraryPicker,
                scope: $dashboardScopeStore.scope)
            }
          } else {
            ToolbarItem(placement: .confirmationAction) {
              LibraryScopeMenu(
                libraries: scopeStore.libraries,
                showLibraryPicker: $showLibraryPicker,
                scope: $dashboardScopeStore.scope)
            }
            if #available(iOS 26.0, *) {
              ToolbarSpacer(.fixed, placement: .confirmationAction)
            }
          }
        #endif

        ToolbarItem(placement: .confirmationAction) {
          if isOffline {
            Button {
              Task {
                await tryReconnect()
              }
            } label: {
              if isCheckingConnection {
                LoadingIcon()
              } else {
                Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
              }
            }
            .disabled(isCheckingConnection)
            .help(String(localized: "Check Server Connection"))
            .accessibilityLabel(String(localized: "Check Server Connection"))
          } else if isRefreshing {
            Button {
            } label: {
              LoadingIcon()
            }
          } else {
            Menu {
              NavigationLink(value: NavDestination.settingsReadingStats) {
                Label(ServerSection.readingStats.title, systemImage: "chart.bar.doc.horizontal")
              }

              Divider()

              Button {
                Task {
                  await refreshDashboard(reason: "Manual toolbar button")
                }
              } label: {
                Label(String(localized: "Refresh Dashboard"), systemImage: "arrow.clockwise")
              }

              Button {
                enterOfflineMode()
              } label: {
                Label(String(localized: "Enter Offline Mode"), systemImage: "wifi.slash")
              }
            } label: {
              Image(systemName: "ellipsis")
            }
          }
        }
      }
      .refreshableWithMinimumHold {
        // The refresh control is the pull gesture's own indicator, so the
        // toolbar stays untouched; swapping it mid-gesture stutters the
        // pin and bounce-back animations.
        await refreshDashboard(reason: "Pull to refresh", showsToolbarIndicator: false)
      }
      .sheet(isPresented: $showLibraryPicker) {
        LibraryPickerSheet()
      }
    #endif
    #if os(tvOS)
      .sheet(isPresented: $showLibraryPicker) {
        LibraryPickerSheet()
      }
    #endif
  }

  private func tryReconnect() async {
    withAnimation {
      isCheckingConnection = true
    }
    let serverReachable = await authViewModel.loadCurrentUser()
    let reconnected = serverReachable && AppConfig.isLoggedIn
    if reconnected {
      AppConfig.exitOfflineMode()
    }
    // If unreachable: stay in current offline mode. We deliberately do not call
    // `enterAutoOfflineMode()` here — the user invoked the reconnect manually
    // from a state that may have been either auto or manual, and a failed retry
    // should preserve that classification rather than reclassifying as auto.
    withAnimation {
      isCheckingConnection = false
    }

    if reconnected {
      await sseService.connect()
      ErrorManager.shared.notify(message: String(localized: "settings.connection_restored"))
      await refreshDashboard(reason: "Reconnected")
    }
  }

  private func enterOfflineMode() {
    guard !isOffline else { return }

    DashboardRefreshCoordinator.shared.cancelPendingAutoRefresh(clearDeferred: true)
    AppConfig.enterManualOfflineMode()

    Task {
      await sseService.disconnect(notify: false)
    }
  }
}
