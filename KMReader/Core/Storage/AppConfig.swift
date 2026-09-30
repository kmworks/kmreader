//
// AppConfig.swift
//
//

import Foundation

/// Centralized configuration management using UserDefaults
enum AppConfig {
  // MARK: - Server & Auth
  static nonisolated var current: Current {
    get {
      if let rawValue = UserDefaults.standard.string(forKey: "currentAccount"),
        let current = Current(rawValue: rawValue)
      {
        return current
      }
      return Current()
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "currentAccount")
    }
  }

  static nonisolated var requestTimeout: Double {
    get {
      if UserDefaults.standard.object(forKey: "requestTimeout") != nil {
        return UserDefaults.standard.double(forKey: "requestTimeout")
      }
      return 15.0
    }
    set { UserDefaults.standard.set(newValue, forKey: "requestTimeout") }
  }

  static nonisolated var downloadTimeout: Double {
    get {
      if UserDefaults.standard.object(forKey: "downloadTimeout") != nil {
        return UserDefaults.standard.double(forKey: "downloadTimeout")
      }
      return 60.0
    }
    set { UserDefaults.standard.set(newValue, forKey: "downloadTimeout") }
  }

  static nonisolated var authTimeout: Double {
    get {
      if UserDefaults.standard.object(forKey: "authTimeout") != nil {
        return UserDefaults.standard.double(forKey: "authTimeout")
      }
      return 5.0
    }
    set { UserDefaults.standard.set(newValue, forKey: "authTimeout") }
  }

  static nonisolated var apiRetryCount: Int {
    get {
      if UserDefaults.standard.object(forKey: "apiRetryCount") != nil {
        return UserDefaults.standard.integer(forKey: "apiRetryCount")
      }
      return 0
    }
    set { UserDefaults.standard.set(newValue, forKey: "apiRetryCount") }
  }

  static nonisolated var isLoggedIn: Bool {
    get { UserDefaults.standard.bool(forKey: "isLoggedInV2") }
    set { UserDefaults.standard.set(newValue, forKey: "isLoggedInV2") }
  }

  static nonisolated var showProtectedServers: Bool {
    get { UserDefaults.standard.bool(forKey: "showProtectedServers") }
    set { UserDefaults.standard.set(newValue, forKey: "showProtectedServers") }
  }

  static nonisolated var deviceIdentifier: String {
    get { UserDefaults.standard.string(forKey: "deviceIdentifier") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "deviceIdentifier") }
  }

  static nonisolated var userAgent: String {
    get { UserDefaults.standard.string(forKey: "userAgent") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "userAgent") }
  }

  static nonisolated var isolateCoverPage: Bool {
    get {
      if UserDefaults.standard.object(forKey: "isolateCoverPage") != nil {
        return UserDefaults.standard.bool(forKey: "isolateCoverPage")
      }
      return true
    }
    set { UserDefaults.standard.set(newValue, forKey: "isolateCoverPage") }
  }

  static nonisolated var splitWidePageMode: SplitWidePageMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "splitWidePageMode"),
        let mode = SplitWidePageMode(rawValue: stored)
      {
        return mode
      }
      return .none
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "splitWidePageMode") }
  }

  static nonisolated var enableDivinaImageContextMenu: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableDivinaImageContextMenu") != nil {
        return UserDefaults.standard.bool(forKey: "enableDivinaImageContextMenu")
      }
      return false
    }
    set { UserDefaults.standard.set(newValue, forKey: "enableDivinaImageContextMenu") }
  }

  static nonisolated var divinaPreloadProfile: ReaderPreloadProfile {
    get {
      if let stored = UserDefaults.standard.string(forKey: "divinaPreloadProfile"),
        let profile = ReaderPreloadProfile(rawValue: stored)
      {
        return profile
      }
      return .balanced
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "divinaPreloadProfile") }
  }

  static nonisolated var showDivinaControlsGradientBackground: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showDivinaControlsGradientBackground") != nil {
        return UserDefaults.standard.bool(forKey: "showDivinaControlsGradientBackground")
      }
      return false
    }
    set { UserDefaults.standard.set(newValue, forKey: "showDivinaControlsGradientBackground") }
  }

  static nonisolated var showDivinaProgressBarWhileReading: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showDivinaProgressBarWhileReading") != nil {
        return UserDefaults.standard.bool(forKey: "showDivinaProgressBarWhileReading")
      }
      return true
    }
    set { UserDefaults.standard.set(newValue, forKey: "showDivinaProgressBarWhileReading") }
  }

  static nonisolated var pdfOfflineRenderQuality: PdfOfflineRenderQuality {
    get {
      if let stored = UserDefaults.standard.string(forKey: "pdfOfflineRenderQuality"),
        let quality = PdfOfflineRenderQuality(rawValue: stored)
      {
        return quality
      }
      return .high
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "pdfOfflineRenderQuality") }
  }

  static nonisolated var pdfPagePresentation: PdfPagePresentation {
    get {
      if let stored = UserDefaults.standard.string(forKey: "pdfPagePresentation"),
        let presentation = PdfPagePresentation(rawValue: stored)
      {
        return presentation
      }
      return .auto
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "pdfPagePresentation") }
  }

  static nonisolated var pdfIsolateCoverPage: Bool {
    get {
      if UserDefaults.standard.object(forKey: "pdfIsolateCoverPage") != nil {
        return UserDefaults.standard.bool(forKey: "pdfIsolateCoverPage")
      }
      return true
    }
    set { UserDefaults.standard.set(newValue, forKey: "pdfIsolateCoverPage") }
  }

  static nonisolated var showPdfControlsGradientBackground: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showPdfControlsGradientBackground") != nil {
        return UserDefaults.standard.bool(forKey: "showPdfControlsGradientBackground")
      }
      return false
    }
    set { UserDefaults.standard.set(newValue, forKey: "showPdfControlsGradientBackground") }
  }

  static nonisolated var showPdfProgressBarWhileReading: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showPdfProgressBarWhileReading") != nil {
        return UserDefaults.standard.bool(forKey: "showPdfProgressBarWhileReading")
      }
      return true
    }
    set { UserDefaults.standard.set(newValue, forKey: "showPdfProgressBarWhileReading") }
  }

  static nonisolated var isOffline: Bool {
    get { UserDefaults.standard.bool(forKey: "isOffline") }
    set { UserDefaults.standard.set(newValue, forKey: "isOffline") }
  }

  /// Records whether the current offline-mode state was entered automatically
  /// (e.g., from connection failures, bootstrap failures) vs. manually (the user
  /// explicitly tapped "Enter Offline Mode" in the dashboard menu).
  ///
  /// Used to gate automatic recovery: only auto-entered offline mode should be
  /// auto-exited when the network returns. Manually-entered offline mode is
  /// sticky and only exits via an explicit user action (tap the wifi-slash
  /// icon, log in, etc.).
  static nonisolated var offlineWasAutomatic: Bool {
    get { UserDefaults.standard.bool(forKey: "offlineWasAutomatic") }
    set { UserDefaults.standard.set(newValue, forKey: "offlineWasAutomatic") }
  }

  /// Transition to offline mode because a connection failure or bootstrap step
  /// failed. Eligible for automatic recovery when the configured server becomes
  /// reachable again.
  ///
  /// **No-op when already offline** — preserves the existing provenance flag.
  /// This is important: a failed network probe at app boot must not silently
  /// convert a user's previously-manual offline mode into auto-offline (which
  /// would then become eligible for automatic recovery against their intent).
  ///
  /// Sets `offlineWasAutomatic` *before* `isOffline` so that any `@AppStorage`
  /// observer reacting to the `isOffline` change sees the freshly-set
  /// provenance flag (avoids any race where the observer fires while the
  /// provenance is still stale).
  static nonisolated func enterAutoOfflineMode() {
    guard !isOffline else { return }
    offlineWasAutomatic = true
    isOffline = true
  }

  /// Transition to offline mode because the user explicitly opted in via the
  /// dashboard menu. NOT eligible for automatic recovery — the user has to
  /// explicitly tap to reconnect.
  static nonisolated func enterManualOfflineMode() {
    offlineWasAutomatic = false
    isOffline = true
  }

  /// Exit offline mode. Resets both flags so the next entry can correctly
  /// classify itself. Safe to call when already online (idempotent).
  static nonisolated func exitOfflineMode() {
    offlineWasAutomatic = false
    isOffline = false
  }

  /// One-time migration to classify a persisted `isOffline = true` state as
  /// auto-offline for users upgrading from a version that did not track
  /// offline-mode provenance. Without this, an upgraded user whose previous
  /// session left them offline would be stuck in fake-manual-offline (the
  /// default `offlineWasAutomatic = false`) and the new auto-recovery loop
  /// would never run.
  ///
  /// Conservatively classifies the persisted state as auto: users who genuinely
  /// wanted manual offline would normally re-enter it explicitly post-upgrade,
  /// and the alternative (leaving them stranded) is worse.
  ///
  /// Idempotent via a marker key in UserDefaults. Safe to call on every launch;
  /// subsequent invocations are no-ops.
  static nonisolated func migrateOfflineProvenanceIfNeeded() {
    let migrationKey = "offlineProvenanceMigrated_v1"
    guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
    UserDefaults.standard.set(true, forKey: migrationKey)
    if isOffline {
      offlineWasAutomatic = true
    }
  }

  /// Cleans up the accent-color preference persisted by the removed theme feature.
  static nonisolated func removeLegacyThemeColor() {
    UserDefaults.standard.removeObject(forKey: "themeColorHex")
  }

  /// Carries over the Keep Reading horizontal-card toggle removed in 6.5
  /// (`dashboardHorizontalBookCards`, on by default): off meant the regular
  /// book card, so it maps to a Keep Reading `large` override. Remove once
  /// upgrades from 6.4 are no longer expected.
  static nonisolated func migrateLegacyHorizontalBookCards() {
    let legacyKey = "dashboardHorizontalBookCards"
    guard UserDefaults.standard.object(forKey: legacyKey) != nil else { return }
    if !UserDefaults.standard.bool(forKey: legacyKey) {
      var configuration = dashboard
      if configuration.cardKindOverrides[.keepReading] == nil {
        configuration.cardKindOverrides[.keepReading] = .large
        dashboard = configuration
      }
    }
    UserDefaults.standard.removeObject(forKey: legacyKey)
  }

  static nonisolated var maxPageCacheSize: Int {
    get {
      if UserDefaults.standard.object(forKey: "maxPageCacheSize") != nil {
        return UserDefaults.standard.integer(forKey: "maxPageCacheSize")
      }
      return 8  // Default 8 GB
    }
    set { UserDefaults.standard.set(newValue, forKey: "maxPageCacheSize") }
  }

  static nonisolated var maxCoverCacheSize: Int {
    get {
      if UserDefaults.standard.object(forKey: "maxCoverCacheSize") != nil {
        return UserDefaults.standard.integer(forKey: "maxCoverCacheSize")
      }
      return 512  // Default 512 MB
    }
    set { UserDefaults.standard.set(newValue, forKey: "maxCoverCacheSize") }
  }

  static nonisolated var coverCacheExpirationDays: Int {
    get {
      if UserDefaults.standard.object(forKey: "coverCacheExpirationDays") != nil {
        return max(1, UserDefaults.standard.integer(forKey: "coverCacheExpirationDays"))
      }
      return 7
    }
    set { UserDefaults.standard.set(max(1, newValue), forKey: "coverCacheExpirationDays") }
  }

  static nonisolated var coverCacheExpirationInterval: TimeInterval {
    TimeInterval(coverCacheExpirationDays * 24 * 60 * 60)
  }

  // MARK: - SSE (Server-Sent Events)
  static nonisolated var enableSSE: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableSSE") != nil {
        return UserDefaults.standard.bool(forKey: "enableSSE")
      }
      return true  // Default to enabled
    }
    set { UserDefaults.standard.set(newValue, forKey: "enableSSE") }
  }

  static nonisolated var enableSSENotify: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableSSENotify") != nil {
        return UserDefaults.standard.bool(forKey: "enableSSENotify")
      }
      return false  // Default to disabled
    }
    set { UserDefaults.standard.set(newValue, forKey: "enableSSENotify") }
  }

  static nonisolated var enableSSEAutoRefresh: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableSSEAutoRefresh") != nil {
        return UserDefaults.standard.bool(forKey: "enableSSEAutoRefresh")
      }
      return true  // Default to enabled
    }
    set { UserDefaults.standard.set(newValue, forKey: "enableSSEAutoRefresh") }
  }

  static nonisolated var taskQueueStatus: TaskQueueSSEDto {
    get {
      guard let rawValue = UserDefaults.standard.string(forKey: "taskQueueStatus"),
        !rawValue.isEmpty,
        let status = TaskQueueSSEDto(rawValue: rawValue)
      else {
        return TaskQueueSSEDto()
      }
      return status
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "taskQueueStatus")
    }
  }

  static nonisolated var offlinePaused: Bool {
    get { UserDefaults.standard.bool(forKey: "offlinePaused") }
    set { UserDefaults.standard.set(newValue, forKey: "offlinePaused") }
  }

  static nonisolated var offlineAutoDeleteRead: Bool {
    get { UserDefaults.standard.bool(forKey: "offlineAutoDeleteRead") }
    set { UserDefaults.standard.set(newValue, forKey: "offlineAutoDeleteRead") }
  }

  static nonisolated var offlineFirstReading: Bool {
    get { UserDefaults.standard.bool(forKey: "offlineFirstReading") }
    set { UserDefaults.standard.set(newValue, forKey: "offlineFirstReading") }
  }

  static nonisolated var backgroundDownloadTasksData: Data? {
    get { UserDefaults.standard.data(forKey: "BackgroundDownloadTasks") }
    set {
      if let value = newValue {
        UserDefaults.standard.set(value, forKey: "BackgroundDownloadTasks")
      } else {
        UserDefaults.standard.removeObject(forKey: "BackgroundDownloadTasks")
      }
    }
  }

  // MARK: - Custom Fonts
  static nonisolated var customFontNames: [String] {
    get {
      UserDefaults.standard.stringArray(forKey: "customFontNames") ?? []
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "customFontNames")
    }
  }

  // MARK: - Appearance
  static nonisolated var showDashboardSectionGradientBackground: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showDashboardSectionGradientBackground") != nil {
        return UserDefaults.standard.bool(forKey: "showDashboardSectionGradientBackground")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "showDashboardSectionGradientBackground")
    }
  }

  /// Next-book suggestions skip books already read, like the dashboard.
  static nonisolated var suggestNextUnreadBook: Bool {
    get {
      if UserDefaults.standard.object(forKey: "suggestNextUnreadBook") != nil {
        return UserDefaults.standard.bool(forKey: "suggestNextUnreadBook")
      }
      return true
    }
    set { UserDefaults.standard.set(newValue, forKey: "suggestNextUnreadBook") }
  }

  /// Opt-in: ordered read lists the user reads through continue like series
  /// (reader order from any entry point, the Read Lists in Progress section).
  static nonisolated var readListContinuationEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: "readListContinuationEnabled") }
    set { UserDefaults.standard.set(newValue, forKey: "readListContinuationEnabled") }
  }

  // MARK: - Browse Layouts
  static nonisolated var seriesBrowseLayout: BrowseLayoutMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "seriesBrowseLayout"),
        let layout = BrowseLayoutMode(rawValue: stored)
      {
        return layout
      }
      return .grid
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "seriesBrowseLayout")
    }
  }

  static nonisolated var collectionBrowseLayout: BrowseLayoutMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "collectionBrowseLayout"),
        let layout = BrowseLayoutMode(rawValue: stored)
      {
        return layout
      }
      return .grid
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "collectionBrowseLayout")
    }
  }

  static nonisolated var bookBrowseLayout: BrowseLayoutMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "bookBrowseLayout"),
        let layout = BrowseLayoutMode(rawValue: stored)
      {
        return layout
      }
      return .grid
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "bookBrowseLayout")
    }
  }

  static nonisolated var readListBrowseLayout: BrowseLayoutMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "readListBrowseLayout"),
        let layout = BrowseLayoutMode(rawValue: stored)
      {
        return layout
      }
      return .grid
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "readListBrowseLayout")
    }
  }

  // MARK: - Detail Layouts
  static nonisolated var seriesDetailLayout: BrowseLayoutMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "seriesDetailLayout"),
        let layout = BrowseLayoutMode(rawValue: stored)
      {
        return layout
      }
      return .list
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "seriesDetailLayout")
    }
  }

  static nonisolated var collectionDetailLayout: BrowseLayoutMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "collectionDetailLayout"),
        let layout = BrowseLayoutMode(rawValue: stored)
      {
        return layout
      }
      return .list
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "collectionDetailLayout")
    }
  }

  static nonisolated var readListDetailLayout: BrowseLayoutMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "readListDetailLayout"),
        let layout = BrowseLayoutMode(rawValue: stored)
      {
        return layout
      }
      return .list
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "readListDetailLayout")
    }
  }

  // MARK: - Browse Options Raw Values
  static nonisolated var seriesBrowseOptions: String {
    get { UserDefaults.standard.string(forKey: "seriesBrowseOptions") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "seriesBrowseOptions") }
  }

  static nonisolated var bookBrowseOptions: String {
    get { UserDefaults.standard.string(forKey: "bookBrowseOptions") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "bookBrowseOptions") }
  }

  static nonisolated var collectionSeriesBrowseOptions: String {
    get { UserDefaults.standard.string(forKey: "collectionSeriesBrowseOptions") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "collectionSeriesBrowseOptions") }
  }

  static nonisolated var readListBookBrowseOptions: String {
    get { UserDefaults.standard.string(forKey: "readListBookBrowseOptions") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "readListBookBrowseOptions") }
  }

  static nonisolated var seriesBookBrowseOptions: String {
    get { UserDefaults.standard.string(forKey: "seriesBookBrowseOptions") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "seriesBookBrowseOptions") }
  }

  static nonisolated var coverOnlyCards: Bool {
    get {
      if UserDefaults.standard.object(forKey: "coverOnlyCards") != nil {
        return UserDefaults.standard.bool(forKey: "coverOnlyCards")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "coverOnlyCards")
    }
  }

  static nonisolated var showBookCardSeriesTitle: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showBookCardSeriesTitle") != nil {
        return UserDefaults.standard.bool(forKey: "showBookCardSeriesTitle")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "showBookCardSeriesTitle")
    }
  }

  static nonisolated var thumbnailPreserveAspectRatio: Bool {
    get {
      if UserDefaults.standard.object(forKey: "thumbnailPreserveAspectRatio") != nil {
        return UserDefaults.standard.bool(forKey: "thumbnailPreserveAspectRatio")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "thumbnailPreserveAspectRatio")
    }
  }

  static nonisolated var privacyProtection: Bool {
    get {
      UserDefaults.standard.bool(forKey: "privacyProtection")
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "privacyProtection")
    }
  }

  static nonisolated var searchIgnoreFilters: Bool {
    get {
      if UserDefaults.standard.object(forKey: "searchIgnoreFilters") != nil {
        return UserDefaults.standard.bool(forKey: "searchIgnoreFilters")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "searchIgnoreFilters")
    }
  }

  // MARK: - Reader
  static nonisolated var showTapZoneHints: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showTapZoneHints") != nil {
        return UserDefaults.standard.bool(forKey: "showTapZoneHints")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "showTapZoneHints")
    }
  }

  static nonisolated var tapZoneMode: TapZoneMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "tapZoneMode"),
        let mode = TapZoneMode(rawValue: stored)
      {
        return mode
      }
      return .defaultLayout
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "tapZoneMode")
    }
  }

  static nonisolated var tapZoneInversionMode: TapZoneInversionMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "tapZoneInversionMode"),
        let mode = TapZoneInversionMode(rawValue: stored)
      {
        return mode
      }
      return .auto
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "tapZoneInversionMode")
    }
  }

  static nonisolated var epubTapZoneMode: TapZoneMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "epubTapZoneMode"),
        let mode = TapZoneMode(rawValue: stored)
      {
        return mode
      }

      return .defaultLayout
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "epubTapZoneMode")
    }
  }

  static nonisolated var epubTapZoneInversionMode: TapZoneInversionMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "epubTapZoneInversionMode"),
        let mode = TapZoneInversionMode(rawValue: stored)
      {
        return mode
      }

      return .auto
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "epubTapZoneInversionMode")
    }
  }

  static nonisolated var showKeyboardHelpOverlay: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showKeyboardHelpOverlay") != nil {
        return UserDefaults.standard.bool(forKey: "showKeyboardHelpOverlay")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "showKeyboardHelpOverlay")
    }
  }

  static nonisolated var pdfShowKeyboardHelpOverlay: Bool {
    get {
      if UserDefaults.standard.object(forKey: "pdfShowKeyboardHelpOverlay") != nil {
        return UserDefaults.standard.bool(forKey: "pdfShowKeyboardHelpOverlay")
      }

      let migratedValue: Bool
      if UserDefaults.standard.object(forKey: "showKeyboardHelpOverlay") != nil {
        migratedValue = UserDefaults.standard.bool(forKey: "showKeyboardHelpOverlay")
      } else {
        migratedValue = true
      }

      UserDefaults.standard.set(migratedValue, forKey: "pdfShowKeyboardHelpOverlay")
      return migratedValue
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "pdfShowKeyboardHelpOverlay")
    }
  }

  static nonisolated var epubShowKeyboardHelpOverlay: Bool {
    get {
      if UserDefaults.standard.object(forKey: "epubShowKeyboardHelpOverlay") != nil {
        return UserDefaults.standard.bool(forKey: "epubShowKeyboardHelpOverlay")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "epubShowKeyboardHelpOverlay")
    }
  }

  static nonisolated var enableReaderLiveActivity: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableReaderLiveActivity") != nil {
        return UserDefaults.standard.bool(forKey: "enableReaderLiveActivity")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "enableReaderLiveActivity")
    }
  }

  static nonisolated var autoFullscreenOnOpen: Bool {
    get {
      if UserDefaults.standard.object(forKey: "autoFullscreenOnOpen") != nil {
        return UserDefaults.standard.bool(forKey: "autoFullscreenOnOpen")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "autoFullscreenOnOpen")
    }
  }

  static nonisolated var readerBackground: ReaderBackground {
    get {
      if let stored = UserDefaults.standard.string(forKey: "readerBackground"),
        let background = ReaderBackground(rawValue: stored)
      {
        return background
      }
      return .system
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "readerBackground")
    }
  }

  static nonisolated var useNativePdfReader: Bool {
    get {
      if UserDefaults.standard.object(forKey: "useNativePdfReader") != nil {
        return UserDefaults.standard.bool(forKey: "useNativePdfReader")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "useNativePdfReader")
    }
  }

  static nonisolated var pageLayout: PageLayout {
    get {
      if let stored = UserDefaults.standard.string(forKey: "pageLayout") {
        if stored == "dual" {
          return .auto
        }
        if let layout = PageLayout(rawValue: stored) {
          return layout
        }
      }
      return .auto
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "pageLayout")
    }
  }

  static nonisolated var forceDefaultReadingDirection: Bool {
    get {
      if UserDefaults.standard.object(forKey: "forceDefaultReadingDirection") != nil {
        return UserDefaults.standard.bool(forKey: "forceDefaultReadingDirection")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "forceDefaultReadingDirection")
    }
  }

  static nonisolated var defaultReadingDirection: ReadingDirection {
    get {
      if let stored = UserDefaults.standard.string(forKey: "defaultReadingDirection"),
        let direction = ReadingDirection(rawValue: stored)
      {
        return direction
      }
      return .ltr
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "defaultReadingDirection")
    }
  }

  static nonisolated var webtoonPageWidthPercentage: Double {
    get {
      if UserDefaults.standard.object(forKey: "webtoonPageWidthPercentage") != nil {
        return UserDefaults.standard.double(forKey: "webtoonPageWidthPercentage")
      }
      return 100.0
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "webtoonPageWidthPercentage")
    }
  }

  static nonisolated var webtoonTapScrollPercentage: Double {
    get {
      if UserDefaults.standard.object(forKey: "webtoonTapScrollPercentage") != nil {
        return UserDefaults.standard.double(forKey: "webtoonTapScrollPercentage")
      }
      return 80.0
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "webtoonTapScrollPercentage")
    }
  }

  static nonisolated var showPageNumber: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showPageNumber") != nil {
        return UserDefaults.standard.bool(forKey: "showPageNumber")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "showPageNumber")
    }
  }

  static nonisolated var showPageShadow: Bool {
    get {
      if UserDefaults.standard.object(forKey: "showPageShadow") != nil {
        return UserDefaults.standard.bool(forKey: "showPageShadow")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "showPageShadow")
    }
  }

  static nonisolated var animateTapTurns: Bool {
    get {
      if UserDefaults.standard.object(forKey: "animateTapTurns") != nil {
        return UserDefaults.standard.bool(forKey: "animateTapTurns")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "animateTapTurns")
    }
  }

  /// Page turns from the session's starting page required before an unread or
  /// finished book records read progress; 0 records immediately. Guards against
  /// accidental reader opens; a book already in progress records any page turn.
  static nonisolated var progressRecordingThreshold: Int {
    get {
      if UserDefaults.standard.object(forKey: "progressRecordingThreshold") != nil {
        return UserDefaults.standard.integer(forKey: "progressRecordingThreshold")
      }
      return 3
    }
    set {
      UserDefaults.standard.set(max(0, newValue), forKey: "progressRecordingThreshold")
    }
  }

  static nonisolated var animateEpubTapTurns: Bool {
    get {
      if UserDefaults.standard.object(forKey: "animateEpubTapTurns") != nil {
        return UserDefaults.standard.bool(forKey: "animateEpubTapTurns")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "animateEpubTapTurns")
    }
  }

  static nonisolated var epubTapScrollPercentage: Double {
    get {
      if UserDefaults.standard.object(forKey: "epubTapScrollPercentage") != nil {
        return UserDefaults.standard.double(forKey: "epubTapScrollPercentage")
      }
      return 80.0
    }
    set {
      UserDefaults.standard.set(min(100.0, max(25.0, newValue)), forKey: "epubTapScrollPercentage")
    }
  }

  static nonisolated var pageTransitionStyle: PageTransitionStyle {
    get {
      if let stored = UserDefaults.standard.string(forKey: "pageTransitionStyle"),
        let style = PageTransitionStyle(rawValue: stored)
      {
        return style
      }
      return .cover
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "pageTransitionStyle")
    }
  }

  static nonisolated var doubleTapZoomScale: Double {
    get {
      if UserDefaults.standard.object(forKey: "doubleTapZoomScale") != nil {
        return UserDefaults.standard.double(forKey: "doubleTapZoomScale")
      }
      return 2.0
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "doubleTapZoomScale")
    }
  }

  static nonisolated var doubleTapZoomMode: DoubleTapZoomMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "doubleTapZoomMode"),
        let mode = DoubleTapZoomMode(rawValue: stored)
      {
        return mode
      }
      return .enabled
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "doubleTapZoomMode")
    }
  }

  static nonisolated var enableLiveText: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableLiveText") != nil {
        return UserDefaults.standard.bool(forKey: "enableLiveText")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "enableLiveText")
    }
  }

  static nonisolated var imageUpscalingMode: ReaderImageUpscalingMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "imageUpscalingMode"),
        let mode = ReaderImageUpscalingMode(rawValue: stored)
      {
        return mode
      }
      return .disabled
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "imageUpscalingMode")
    }
  }

  static nonisolated var imageUpscaleAutoTriggerScale: Double {
    get {
      if UserDefaults.standard.object(forKey: "imageUpscaleAutoTriggerScale") != nil {
        return max(UserDefaults.standard.double(forKey: "imageUpscaleAutoTriggerScale"), 1.0)
      }
      return 1.05
    }
    set {
      UserDefaults.standard.set(max(newValue, 1.0), forKey: "imageUpscaleAutoTriggerScale")
    }
  }

  static nonisolated var imageUpscaleAlwaysMaxScreenScale: Double {
    get {
      if UserDefaults.standard.object(forKey: "imageUpscaleAlwaysMaxScreenScale") != nil {
        return max(UserDefaults.standard.double(forKey: "imageUpscaleAlwaysMaxScreenScale"), 1.0)
      }
      return 1.5
    }
    set {
      UserDefaults.standard.set(max(newValue, 1.0), forKey: "imageUpscaleAlwaysMaxScreenScale")
    }
  }

  static nonisolated var divinaPageBorderCropMode: ReaderPageBorderCropMode {
    get {
      if let stored = UserDefaults.standard.string(forKey: "divinaPageBorderCropMode"),
        let mode = ReaderPageBorderCropMode(rawValue: stored)
      {
        return mode
      }
      return .disabled
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "divinaPageBorderCropMode")
    }
  }

  static nonisolated var shakeToOpenLiveText: Bool {
    get {
      if UserDefaults.standard.object(forKey: "shakeToOpenLiveText") != nil {
        return UserDefaults.standard.bool(forKey: "shakeToOpenLiveText")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "shakeToOpenLiveText")
    }
  }

  static nonisolated var epubThemePreferences: EpubThemePreferences {
    get {
      if let stored = UserDefaults.standard.string(forKey: "epubPreferences"),
        let prefs = EpubThemePreferences(rawValue: stored)
      {
        return prefs
      }
      return EpubThemePreferences()
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "epubPreferences")
    }
  }

  static nonisolated var epubShowsStatusBarWhileReading: Bool {
    get {
      if UserDefaults.standard.object(forKey: "epubShowsStatusBarWhileReading") != nil {
        return UserDefaults.standard.bool(forKey: "epubShowsStatusBarWhileReading")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "epubShowsStatusBarWhileReading")
    }
  }

  static nonisolated var epubOverlayPreferences: EpubOverlayPreferences {
    get {
      if let stored = UserDefaults.standard.string(forKey: "epubOverlayPreferences"),
        let preferences = EpubOverlayPreferences(rawValue: stored)
      {
        return preferences
      }
      return EpubOverlayPreferences()
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "epubOverlayPreferences")
    }
  }

  // MARK: - Dashboard
  static nonisolated var dashboard: DashboardConfiguration {
    get {
      if let stored = UserDefaults.standard.string(forKey: "dashboard"),
        let config = DashboardConfiguration(rawValue: stored)
      {
        return config
      }
      return DashboardConfiguration()
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "dashboard")
    }
  }

  static nonisolated var dashboardSectionCache: DashboardSectionCache {
    get {
      if let stored = UserDefaults.standard.string(forKey: "dashboardSectionCache"),
        let cache = DashboardSectionCache(rawValue: stored)
      {
        return cache
      }
      return DashboardSectionCache()
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "dashboardSectionCache")
    }
  }

  static nonisolated var readingStatsCache: ReadingStatsCache {
    get {
      if let stored = UserDefaults.standard.string(forKey: "readingStatsCacheV2"),
        let cache = ReadingStatsCache(rawValue: stored)
      {
        return cache
      }
      return ReadingStatsCache()
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "readingStatsCacheV2")
    }
  }

  private static nonisolated var recentlyReadRecordTimeByInstance: [String: TimeInterval] {
    get {
      guard
        let stored = UserDefaults.standard.string(forKey: "recentlyReadRecordTimeByInstance"),
        let data = stored.data(using: .utf8),
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: TimeInterval]
      else {
        return [:]
      }
      return dict
    }
    set {
      if newValue.isEmpty {
        UserDefaults.standard.removeObject(forKey: "recentlyReadRecordTimeByInstance")
        return
      }

      guard
        let data = try? JSONSerialization.data(withJSONObject: newValue, options: [.sortedKeys]),
        let encoded = String(data: data, encoding: .utf8)
      else {
        return
      }
      UserDefaults.standard.set(encoded, forKey: "recentlyReadRecordTimeByInstance")
    }
  }

  static nonisolated func recentlyReadRecordTime(instanceId: String) -> Date? {
    guard !instanceId.isEmpty, let timestamp = recentlyReadRecordTimeByInstance[instanceId] else {
      return nil
    }
    return Date(timeIntervalSince1970: timestamp)
  }

  static nonisolated func setRecentlyReadRecordTime(_ date: Date, instanceId: String) {
    guard !instanceId.isEmpty else { return }
    var store = recentlyReadRecordTimeByInstance
    store[instanceId] = date.timeIntervalSince1970
    recentlyReadRecordTimeByInstance = store
  }

  private static nonisolated var readingProgressSyncTimeByInstance: [String: TimeInterval] {
    get {
      guard
        let stored = UserDefaults.standard.string(forKey: "readingProgressSyncTimeByInstance"),
        let data = stored.data(using: .utf8),
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: TimeInterval]
      else {
        return [:]
      }
      return dict
    }
    set {
      if newValue.isEmpty {
        UserDefaults.standard.removeObject(forKey: "readingProgressSyncTimeByInstance")
        return
      }

      guard
        let data = try? JSONSerialization.data(withJSONObject: newValue, options: [.sortedKeys]),
        let encoded = String(data: data, encoding: .utf8)
      else {
        return
      }
      UserDefaults.standard.set(encoded, forKey: "readingProgressSyncTimeByInstance")
    }
  }

  static nonisolated func readingProgressSyncTime(instanceId: String) -> Date? {
    guard !instanceId.isEmpty, let timestamp = readingProgressSyncTimeByInstance[instanceId] else {
      return nil
    }
    return Date(timeIntervalSince1970: timestamp)
  }

  static nonisolated func setReadingProgressSyncTime(_ date: Date, instanceId: String) {
    guard !instanceId.isEmpty else { return }
    var store = readingProgressSyncTimeByInstance
    store[instanceId] = date.timeIntervalSince1970
    readingProgressSyncTimeByInstance = store
  }

  // MARK: - Spotlight
  static nonisolated var enableSpotlightIndexing: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableSpotlightIndexing") != nil {
        return UserDefaults.standard.bool(forKey: "enableSpotlightIndexing")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "enableSpotlightIndexing")
    }
  }

  static nonisolated var enableSpotlightBookIndexing: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableSpotlightBookIndexing") != nil {
        return UserDefaults.standard.bool(forKey: "enableSpotlightBookIndexing")
      }
      return true
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "enableSpotlightBookIndexing")
    }
  }

  static nonisolated var enableSpotlightSeriesIndexing: Bool {
    get {
      if UserDefaults.standard.object(forKey: "enableSpotlightSeriesIndexing") != nil {
        return UserDefaults.standard.bool(forKey: "enableSpotlightSeriesIndexing")
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "enableSpotlightSeriesIndexing")
    }
  }

  private static nonisolated var spotlightLibrarySelectionByInstance: [String: [String]] {
    get {
      guard
        let stored = UserDefaults.standard.string(forKey: "spotlightLibrarySelectionByInstance"),
        let data = stored.data(using: .utf8),
        let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]]
      else {
        return [:]
      }
      return dict
    }
    set {
      if newValue.isEmpty {
        UserDefaults.standard.removeObject(forKey: "spotlightLibrarySelectionByInstance")
        return
      }

      guard
        let data = try? JSONSerialization.data(withJSONObject: newValue, options: [.sortedKeys]),
        let encoded = String(data: data, encoding: .utf8)
      else {
        return
      }
      UserDefaults.standard.set(encoded, forKey: "spotlightLibrarySelectionByInstance")
    }
  }

  static nonisolated func spotlightIndexedLibraryIds(instanceId: String) -> [String]? {
    guard !instanceId.isEmpty else { return nil }
    return spotlightLibrarySelectionByInstance[instanceId]
  }

  static nonisolated func setSpotlightIndexedLibraryIds(_ libraryIds: [String], instanceId: String) {
    guard !instanceId.isEmpty else { return }
    var selection = spotlightLibrarySelectionByInstance
    selection[instanceId] = libraryIds
    spotlightLibrarySelectionByInstance = selection
  }

  static nonisolated func clearSpotlightLibrarySelection(instanceId: String) {
    guard !instanceId.isEmpty else { return }
    var selection = spotlightLibrarySelectionByInstance
    selection.removeValue(forKey: instanceId)
    spotlightLibrarySelectionByInstance = selection
  }

  // MARK: - Clear all auth data
  static func clearAuthData(clearCurrent: Bool = false) {
    if clearCurrent {
      current = Current()
    } else {
      var new = current
      new.reset()
      current = new
    }

    showProtectedServers = false
    dashboard.libraryIds = []
    DashboardSectionCacheStore.shared.reset()
  }
}
