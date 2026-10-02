//
// SidebarItemsStore.swift
//
//

import SwiftUI

@Observable
@MainActor
final class SidebarItemsStore {
  private(set) var libraries: [SidebarLibraryItem] = []
  private(set) var collectionsCount: Int?
  private(set) var readListsCount: Int?

  func load(instanceId: String) async {
    guard !instanceId.isEmpty else {
      clearIfNeeded()
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedLibraries = try await database.fetchSidebarLibraries(instanceId: instanceId)
      let loadedCollectionsCount = try await database.fetchSidebarCollectionsCount(
        instanceId: instanceId)
      let loadedReadListsCount = try await database.fetchSidebarReadListsCount(
        instanceId: instanceId)
      apply(
        libraries: loadedLibraries,
        collectionsCount: loadedCollectionsCount,
        readListsCount: loadedReadListsCount
      )
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func clearIfNeeded() {
    guard !libraries.isEmpty || collectionsCount != nil || readListsCount != nil else { return }

    withAnimation {
      libraries = []
      collectionsCount = nil
      readListsCount = nil
    }
  }

  private func apply(
    libraries loadedLibraries: [SidebarLibraryItem],
    collectionsCount loadedCollectionsCount: Int,
    readListsCount loadedReadListsCount: Int
  ) {
    guard
      libraries != loadedLibraries || collectionsCount != loadedCollectionsCount
        || readListsCount != loadedReadListsCount
    else { return }

    withAnimation {
      if libraries != loadedLibraries { libraries = loadedLibraries }
      if collectionsCount != loadedCollectionsCount { collectionsCount = loadedCollectionsCount }
      if readListsCount != loadedReadListsCount { readListsCount = loadedReadListsCount }
    }
  }
}
