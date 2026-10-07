//
// NavDestination.swift
//
//

import Foundation
import SwiftUI

enum NavDestination: Hashable {
  case home
  /// Aggregate browse; only the `.all`/`.pinned` scopes occur (single
  /// libraries are `browseLibrary`).
  case browse(scope: LibraryBrowseScope)
  case browseSearch
  case browseCollections
  case browseReadLists
  case offline
  case server
  case settings

  case browseLibrary(selection: LibrarySelection)

  // Browse with metadata filter
  case browseSeriesWithPublisher(publisher: String)
  case browseSeriesWithAuthor(author: String)
  case browseSeriesWithGenre(genre: String)
  case browseSeriesWithTag(tag: String)
  case browseBooksWithAuthor(author: String)
  case browseBooksWithTag(tag: String)

  case seriesDetail(seriesId: String)
  case bookDetail(bookId: String)
  case oneshotDetail(seriesId: String)
  case collectionDetail(collectionId: String)
  case readListDetail(readListId: String)
  case dashboardSectionDetail(section: DashboardSection)

  case settingsAppearance
  case settingsBrowse
  case settingsDashboard
  case settingsCache
  case settingsDivinaReader
  case settingsReading
  #if os(iOS) || os(macOS)
    case settingsPdfReader
  #endif
  #if os(iOS)
    case settingsEpubTheme
    case settingsEpubSettings
  #endif
  case settingsSSE
  case settingsSystemFeatures
  case settingsNetwork
  case settingsLogs

  case settingsOfflineTasks
  case settingsOfflineBooks

  case settingsLibraries
  case settingsReadingStats
  case settingsServerInfo
  case settingsServerTasks
  case settingsServerSessions
  case settingsServerScheduledTasks
  case settingsHistory
  case settingsMedia
  case settingsMediaAnalysis
  case settingsMediaMissingPosters
  case settingsMediaDuplicateFiles
  case settingsMediaDuplicatePagesKnown
  case settingsMediaDuplicatePagesUnknown

  case settingsServers
  case settingsApiKey
  case settingsAuthenticationActivity
  case settingsAccount
  case settingsAbout

  /// The library selection carried by browse destinations. Pushed
  /// `.browseLibrary` destinations take their selection from the destination
  /// value itself, so tab shells (which have no ambient sidebar selection)
  /// propagate it correctly through `handleNavigation`.
  var librarySelection: LibrarySelection? {
    if case .browseLibrary(let selection) = self {
      return selection
    }
    return nil
  }

  /// Scope binding for a shell-synced browse root: reads the destination's
  /// own scope and forwards in-page picks to the shell's selection writer.
  /// Nil for non-browse destinations — their pages keep a page-local session
  /// scope.
  func libraryScopeBinding(
    apply: @escaping (LibraryBrowseScope) -> Void
  ) -> Binding<LibraryBrowseScope>? {
    switch self {
    case .browse(let scope):
      return Binding(
        get: { scope },
        set: { apply($0) })
    case .browseLibrary(let selection):
      return Binding(
        get: { .library(selection.libraryId) },
        set: { apply($0) })
    default:
      return nil
    }
  }

  @ViewBuilder
  func content(context: AppViewContext) -> some View {
    switch self {
    case .home:
      DashboardView(
        authViewModel: context.authViewModel,
        readerPresentation: context.readerPresentation
      )
    case .browse(_):
      // The scope is carried for the shell's selection mapping; the page
      // reads it back through the shell-provided scope binding.
      BrowseView(authViewModel: context.authViewModel)
    case .browseSearch:
      BrowseView(
        authViewModel: context.authViewModel,
        focusesSearchOnAppear: true
      )
    case .browseCollections:
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .collections
      )
    case .browseReadLists:
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .readlists
      )
    case .offline:
      OfflineView(authViewModel: context.authViewModel)
    case .server:
      ServerView(authViewModel: context.authViewModel)
    case .settings:
      SettingsView()

    // NOTE: library selection passed via environment
    case .browseLibrary(_):
      BrowseView(authViewModel: context.authViewModel)

    case .browseSeriesWithPublisher(let publisher):
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .series,
        metadataFilter: MetadataFilterConfig.forPublisher(publisher)
      )
    case .browseSeriesWithAuthor(let author):
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .series,
        metadataFilter: MetadataFilterConfig.forAuthors([author])
      )
    case .browseSeriesWithGenre(let genre):
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .series,
        metadataFilter: MetadataFilterConfig.forGenres([genre])
      )
    case .browseSeriesWithTag(let tag):
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .series,
        metadataFilter: MetadataFilterConfig.forTags([tag])
      )
    case .browseBooksWithAuthor(let author):
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .books,
        metadataFilter: MetadataFilterConfig.forAuthors([author])
      )
    case .browseBooksWithTag(let tag):
      BrowseView(
        authViewModel: context.authViewModel,
        fixedContent: .books,
        metadataFilter: MetadataFilterConfig.forTags([tag])
      )

    case .seriesDetail(let seriesId):
      SeriesDetailView(seriesId: seriesId)
    case .bookDetail(let bookId):
      BookDetailView(bookId: bookId)
    case .oneshotDetail(let seriesId):
      OneshotDetailView(seriesId: seriesId)
    case .collectionDetail(let collectionId):
      CollectionDetailView(collectionId: collectionId)
    case .readListDetail(let readListId):
      ReadListDetailView(readListId: readListId)
    case .dashboardSectionDetail(let section):
      DashboardSectionDetailView(section: section)

    case .settingsAppearance:
      SettingsAppearanceView()
    case .settingsBrowse:
      SettingsBrowseView()
    case .settingsDashboard:
      SettingsDashboardView()
    case .settingsCache:
      SettingsCacheView()
    case .settingsDivinaReader:
      DivinaPreferencesView()
    case .settingsReading:
      ReaderPreferencesView()
    #if os(iOS) || os(macOS)
      case .settingsPdfReader:
        PdfPreferencesView()
    #endif
    #if os(iOS)
      case .settingsEpubTheme:
        EpubThemePreferencesView()
      case .settingsEpubSettings:
        EpubReaderSettingsView()
    #endif
    case .settingsSSE:
      SettingsSSEView()
    case .settingsSystemFeatures:
      SettingsSystemFeaturesView()
    case .settingsNetwork:
      SettingsNetworkView()
    case .settingsLogs:
      SettingsLogsView()

    case .settingsOfflineTasks:
      OfflineTasksView()
    case .settingsOfflineBooks:
      OfflineBooksView()

    case .settingsLibraries:
      ServerLibrariesView()
    case .settingsReadingStats:
      ServerReadingStatsView()
    case .settingsServerInfo:
      ServerInfoView()
    case .settingsServerTasks:
      ServerTasksView()
    case .settingsServerSessions:
      ServerSessionsView()
    case .settingsServerScheduledTasks:
      ServerScheduledTasksView()
    case .settingsHistory:
      ServerHistoryView()
    case .settingsMedia:
      MediaManagementView()
    case .settingsMediaAnalysis:
      MediaAnalysisView()
    case .settingsMediaMissingPosters:
      MissingPostersView()
    case .settingsMediaDuplicateFiles:
      DuplicateFilesView()
    case .settingsMediaDuplicatePagesKnown:
      DuplicatePagesKnownView()
    case .settingsMediaDuplicatePagesUnknown:
      DuplicatePagesUnknownView()

    case .settingsServers:
      ServerListView(authViewModel: context.authViewModel)
    case .settingsApiKey:
      ApiKeysView()
    case .settingsAuthenticationActivity:
      AccountActivityView()
    case .settingsAccount:
      SettingsAccountView(authViewModel: context.authViewModel)
    case .settingsAbout:
      SettingsAboutView()
    }
  }

  var zoomSourceID: String? {
    switch self {
    case .seriesDetail(let seriesId):
      return seriesId
    case .bookDetail(let bookId):
      return bookId
    case .oneshotDetail(let seriesId):
      return seriesId
    default:
      return nil
    }
  }
}
