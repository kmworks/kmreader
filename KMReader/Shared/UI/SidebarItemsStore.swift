//
// SidebarItemsStore.swift
//
//

import SwiftUI

@Observable
@MainActor
final class SidebarItemsStore {
  private(set) var libraries: [SidebarLibraryItem] = []
  @ObservationIgnored private var loadGeneration = 0

  @discardableResult
  func load(instanceId: String) async -> Bool {
    loadGeneration += 1
    let generation = loadGeneration
    guard !instanceId.isEmpty else {
      clearIfNeeded()
      return true
    }

    do {
      let database = try await DatabaseOperator.database()
      let loadedLibraries = try await database.fetchSidebarLibraries(instanceId: instanceId)
      guard generation == loadGeneration else { return false }
      apply(libraries: loadedLibraries)
      return true
    } catch {
      ErrorManager.shared.alert(error: error)
      return false
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
