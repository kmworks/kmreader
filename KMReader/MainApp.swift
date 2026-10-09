//
// MainApp.swift
//
//

import GRDB
import SwiftUI

#if os(iOS) || os(macOS)
  import CoreSpotlight
#endif

#if os(iOS)
  /// Scene delegate to handle Quick Actions on warm launch
  class ShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
      _ windowScene: UIWindowScene,
      performActionFor shortcutItem: UIApplicationShortcutItem,
      completionHandler: @escaping (Bool) -> Void
    ) {
      QuickActionService.handleShortcut(shortcutItem)
      completionHandler(true)
    }
  }

  /// App delegate to handle background URLSession events and Quick Actions
  class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
      _ application: UIApplication,
      handleEventsForBackgroundURLSession identifier: String,
      completionHandler: @escaping () -> Void
    ) {
      BackgroundDownloadManager.shared.backgroundCompletionHandler = completionHandler
      BackgroundDownloadManager.shared.reconnectSession()
    }

    func application(
      _ application: UIApplication,
      configurationForConnecting connectingSceneSession: UISceneSession,
      options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
      if let shortcutItem = options.shortcutItem {
        QuickActionService.handleShortcut(shortcutItem)
      }
      let config = UISceneConfiguration(
        name: nil, sessionRole: connectingSceneSession.role)
      config.delegateClass = ShortcutSceneDelegate.self
      return config
    }
  }
#endif

@main
struct MainApp: App {
  #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  #endif
  @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system
  #if os(macOS)
    @Environment(\.openWindow) private var openWindow
  #endif

  @State private var databaseQueue: DatabaseQueue?
  @State private var isPreparingDatabase = false
  @State private var databaseFailureDetails: String?
  @State private var authViewModel: AuthViewModel
  @State private var readerPresentation = ReaderPresentationManager()
  private let deepLinkRouter = DeepLinkRouter.shared

  init() {
    PlatformHelper.setup()
    AppConfig.migrateOfflineProvenanceIfNeeded()
    AppConfig.removeLegacyThemeColor()
    AppConfig.migrateLegacyHorizontalBookCards()
    AppConfig.showProtectedServers = false
    _authViewModel = State(initialValue: AuthViewModel())
  }

  @MainActor
  private func prepareDatabaseIfNeeded(forceRetry: Bool = false) async {
    guard databaseQueue == nil, !isPreparingDatabase else { return }
    isPreparingDatabase = true
    defer { isPreparingDatabase = false }
    if forceRetry {
      databaseFailureDetails = nil
    }

    do {
      let queue = try await Task.detached(priority: .userInitiated) {
        try Self.makePreparedDatabaseQueue()
      }.value
      CustomFontStore.shared.configure(with: queue)
      await DatabaseOperator.configure(databaseQueue: queue)
      _ = OfflineManager.shared
      databaseQueue = queue
      Task.detached(priority: .utility) {
        _ = await OfflineManager.shared.cleanupOrphanedFiles()
      }
      #if os(iOS)
        QuickActionService.handlePendingShortcutIfNeeded()
      #endif
      databaseFailureDetails = nil
    } catch {
      let errorMessage = String(describing: error)
      AppLogger(.database).error("Failed to prepare local database: \(errorMessage)")
      databaseFailureDetails = errorMessage
    }
  }

  private nonisolated static func makePreparedDatabaseQueue() throws -> DatabaseQueue {
    let queue = try LocalDatabase.open()
    try LocalDatabase.migrate(queue)
    return queue
  }

  @MainActor
  private func resetLocalDataAndRetryDatabase() async {
    databaseQueue = nil
    databaseFailureDetails = nil

    do {
      try LocalDataResetService.resetAllLocalData()
      authViewModel = AuthViewModel()
      await prepareDatabaseIfNeeded(forceRetry: true)
    } catch {
      let errorMessage = String(describing: error)
      AppLogger(.database).error("Failed to reset local data: \(errorMessage)")
      databaseFailureDetails = errorMessage
    }
  }

  @ViewBuilder
  private func databaseGate<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    if databaseQueue != nil {
      content()
    } else if let databaseFailureDetails {
      StartupFailureView(
        details: databaseFailureDetails,
        onRetry: {
          Task {
            await prepareDatabaseIfNeeded(forceRetry: true)
          }
        },
        onReset: {
          Task {
            await resetLocalDataAndRetryDatabase()
          }
        }
      )
    } else {
      SplashView(isMigration: true)
        .task {
          await prepareDatabaseIfNeeded()
        }
    }
  }

  @ViewBuilder
  private func mainWindowContent() -> some View {
    ContentView(
      authViewModel: authViewModel,
      readerPresentation: readerPresentation
    )
    #if os(macOS)
      .background(
        MacReaderWindowConfigurator(
          readerPresentation: readerPresentation,
          openWindow: {
            openWindow(id: "reader")
          }
        )
      )
      .task {
        PickerWindowOpener.shared.configure { request in
          openWindow(value: request)
        }
      }
      .overlay(alignment: .bottom) {
        NotificationOverlay()
      }
    #endif
    .task {
      await StoreManager.shared.start()
    }
  }

  #if os(macOS)
    @CommandsBuilder
    private var readerCommands: some Commands {
      CommandMenu("Reader") {
        let state = readerPresentation.readerCommandState

        if state.supportsReaderSettings {
          Button("Reader Settings") {
            readerPresentation.showReaderSettingsFromCommand()
          }
          .disabled(!state.isActive)
        }

        if state.supportsBookDetails {
          Button("Book Details") {
            readerPresentation.showBookDetailsFromCommand()
          }
          .disabled(!state.isActive)
        }

        if state.hasTableOfContents || state.supportsPageJump || state.supportsSearch {
          Divider()
        }

        if state.hasTableOfContents {
          Button("Table of Contents") {
            readerPresentation.showTableOfContentsFromCommand()
          }
          .disabled(!state.isActive)
        }

        if state.supportsPageJump {
          Button("Jump to Page") {
            readerPresentation.showPageJumpFromCommand()
          }
          .disabled(!state.isActive || !state.hasPages)
        }

        if state.supportsSearch {
          Button("Search") {
            readerPresentation.showSearchFromCommand()
          }
          .disabled(!state.isActive || !state.canSearch)
        }

        if state.supportsReadingDirectionSelection
          || state.supportsPageLayoutSelection
          || state.supportsRotationSelection
        {
          Divider()
        }

        if state.supportsReadingDirectionSelection {
          Menu("Reading Direction") {
            ForEach(state.availableReadingDirections, id: \.self) { direction in
              Button {
                readerPresentation.setReadingDirectionFromCommand(direction)
              } label: {
                if state.readingDirection == direction {
                  Label(direction.displayName, systemImage: AppIcon.confirm)
                } else {
                  Text(direction.displayName)
                }
              }
            }
          }
          .disabled(!state.isActive)
        }

        if state.supportsPageLayoutSelection {
          Menu("Page Layout") {
            ForEach(PageLayout.allCases, id: \.self) { layout in
              Button {
                readerPresentation.setPageLayoutFromCommand(layout)
              } label: {
                if state.pageLayout == layout {
                  Label(layout.displayName, systemImage: AppIcon.confirm)
                } else {
                  Text(layout.displayName)
                }
              }
            }
          }
          .disabled(!state.isActive)
        }

        if state.supportsRotationSelection {
          Menu("Page Rotation") {
            ForEach(ReaderRotation.allCases, id: \.self) { rotation in
              Button {
                readerPresentation.setRotationFromCommand(rotation)
              } label: {
                if state.rotation == rotation {
                  Label(rotation.displayName, systemImage: AppIcon.confirm)
                } else {
                  Text(rotation.displayName)
                }
              }
            }
          }
          .disabled(!state.isActive)
        }

        if state.supportsDualPageOptions
          || state.supportsSplitWidePageMode
          || state.supportsContinuousScrollToggle
        {
          Divider()
        }

        if state.supportsDualPageOptions {
          Button {
            readerPresentation.toggleSoloCoverPageFromCommand()
          } label: {
            if state.soloCoverPage {
              Label(String(localized: "Solo Cover Page"), systemImage: AppIcon.confirm)
            } else {
              Text(String(localized: "Solo Cover Page"))
            }
          }
          .disabled(!state.isActive)
        }

        if state.supportsSplitWidePageMode {
          Menu("Split Wide Pages") {
            ForEach(SplitWidePageMode.allCases, id: \.self) { mode in
              Button {
                readerPresentation.setSplitWidePageModeFromCommand(mode)
              } label: {
                if state.splitWidePageMode == mode {
                  Label(mode.displayName, systemImage: AppIcon.confirm)
                } else {
                  Text(mode.displayName)
                }
              }
            }
          }
          .disabled(!state.isActive)
        }

        if state.supportsContinuousScrollToggle {
          Button {
            readerPresentation.toggleContinuousScrollFromCommand()
          } label: {
            if state.continuousScroll {
              Label(String(localized: "Continuous Scroll"), systemImage: AppIcon.confirm)
            } else {
              Text(String(localized: "Continuous Scroll"))
            }
          }
          .disabled(!state.isActive)
        }

        if state.supportsBookNavigation {
          Divider()
        }

        if state.supportsBookNavigation {
          Button("Open Previous Book") {
            readerPresentation.openPreviousBookFromCommand()
          }
          .disabled(!state.isActive || !state.canOpenPreviousBook)
        }

        if state.supportsBookNavigation {
          Button("Open Next Book") {
            readerPresentation.openNextBookFromCommand()
          }
          .disabled(!state.isActive || !state.canOpenNextBook)
        }

        if !state.commandPageIDs.isEmpty {
          Divider()

          ForEach(state.commandPageIDs, id: \.self) { pageID in
            let displayPageNumber = state.displayPageNumbersByID[pageID] ?? pageID.pageNumber + 1
            Menu("Page \(displayPageNumber)") {
              Button("Share") {
                readerPresentation.sharePageFromCommand(pageID)
              }
              .disabled(!state.isActive)

              if let soloAction = state.pageSoloActions.first(where: { $0.pageID == pageID }) {
                Divider()
                Button(readerPageSoloTitle(for: soloAction)) {
                  readerPresentation.toggleSoloPageFromCommand(soloAction.pageID)
                }
                .disabled(!state.isActive)
              }
            }
            .disabled(!state.isActive)
          }
        }
      }
    }

    private func readerPageSoloTitle(for action: ReaderPageSoloActions.Action) -> String {
      if action.title == String(localized: "Cancel Solo") {
        return action.title
      }
      return String(localized: "Show Solo")
    }

  #endif

  var body: some Scene {
    WindowGroup {
      databaseGate {
        mainWindowContent()
      }
      .onOpenURL { url in
        deepLinkRouter.handle(url: url)
      }
      #if os(iOS) || os(macOS)
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
          if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            if let deepLink = SpotlightIndexService.deepLink(for: identifier) {
              deepLinkRouter.pendingDeepLink = deepLink
            }
          }
        }
      #endif
      .preferredColorScheme(appColorScheme.colorScheme)
    }
    #if os(macOS)
      .commands {
        readerCommands
      }
    #endif
    #if os(macOS)
      WindowGroup(id: "reader") {
        databaseGate {
          ReaderWindowView(readerPresentation: readerPresentation)
        }
        .preferredColorScheme(appColorScheme.colorScheme)
      }
      .windowToolbarStyle(.unifiedCompact)
      .defaultSize(width: 1200, height: 800)

      Settings {
        databaseGate {
          SettingsView_macOS()
        }
        .preferredColorScheme(appColorScheme.colorScheme)
      }
      .windowToolbarStyle(.unifiedCompact)
      .defaultSize(width: 800, height: 600)

      WindowGroup(for: PickerWindowRequest.self) { $request in
        Group {
          if let request {
            PickerWindowView(request: request)
          }
        }
        .preferredColorScheme(appColorScheme.colorScheme)
      }
      .defaultSize(width: 720, height: 600)
    #endif
  }
}
