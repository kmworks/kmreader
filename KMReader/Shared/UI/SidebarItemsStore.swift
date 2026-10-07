//
// SidebarItemsStore.swift
//
//

import SwiftUI

@Observable
@MainActor
final class SidebarItemsStore {
  private(set) var libraries: [SidebarLibraryItem] = []

  func load(instanceId: String) async {
    guard !instanceId.isEmpty else {
      clearIfNeeded()
      return
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedLibraries = try await database.fetchSidebarLibraries(instanceId: instanceId)
      apply(libraries: loadedLibraries)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func clearIfNeeded() {
    guard !libraries.isEmpty else { return }

    withAnimation {
      libraries = []
    }
  }

  private func apply(libraries loadedLibraries: [SidebarLibraryItem]) {
    guard libraries != loadedLibraries else { return }

    withAnimation {
      libraries = loadedLibraries
    }
  }
}
