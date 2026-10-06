//
// LibraryAction.swift
//
//

import SwiftUI

enum LibraryAction: CaseIterable {
  case scan
  case scanDeep
  case analyze
  case refreshMetadata
  case emptyTrash

  var label: Label<Text, Image> {
    Label(title, systemImage: systemImage)
  }

  private var title: String {
    switch self {
    case .scan:
      return String(localized: "Scan Library Files")
    case .scanDeep:
      return String(localized: "Scan Library Files (Deep)")
    case .analyze:
      return String(localized: "Analyze")
    case .refreshMetadata:
      return String(localized: "Refresh Metadata")
    case .emptyTrash:
      return String(localized: "Empty Trash")
    }
  }

  private var systemImage: String {
    switch self {
    case .scan:
      return "arrow.clockwise"
    case .scanDeep:
      return "arrow.triangle.2.circlepath"
    case .analyze:
      return AppIcon.analyze
    case .refreshMetadata:
      return "arrow.triangle.branch"
    case .emptyTrash:
      return "trash.slash"
    }
  }

  private var notificationMessage: String {
    switch self {
    case .scan:
      return String(localized: "library.list.notify.scanStarted")
    case .scanDeep:
      return String(localized: "library.list.notify.scanDeepStarted")
    case .analyze:
      return String(localized: "library.list.notify.analysisStarted")
    case .refreshMetadata:
      return String(localized: "library.list.notify.metadataRefreshStarted")
    case .emptyTrash:
      return String(localized: "library.list.notify.trashEmptied")
    }
  }

  private func performAction(for libraryId: String) async throws {
    switch self {
    case .scan:
      try await LibraryService.scanLibrary(id: libraryId)
    case .scanDeep:
      try await LibraryService.scanLibrary(id: libraryId, deep: true)
    case .analyze:
      try await LibraryService.analyzeLibrary(id: libraryId)
    case .refreshMetadata:
      try await LibraryService.refreshMetadata(id: libraryId)
    case .emptyTrash:
      try await LibraryService.emptyTrash(id: libraryId)
    }
  }

  func perform(for libraryId: String, completion: (() -> Void)? = nil) {
    Task {
      do {
        try await performAction(for: libraryId)
        ErrorManager.shared.notify(message: notificationMessage)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      if let completion {
        completion()
      }
    }
  }
}
