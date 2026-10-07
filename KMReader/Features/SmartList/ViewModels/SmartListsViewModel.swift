//
// SmartListsViewModel.swift
//
//

import Foundation
import SwiftUI

/// DTO-driven and online-only: smart lists are evaluated server-side and have
/// no local mirror, so there is nothing to show offline.
@MainActor
@Observable
final class SmartListsViewModel {
  private(set) var smartLists: [SmartList] = []
  private(set) var isLoading = false
  private(set) var isSupported = true

  /// Newest load wins: a reload supersedes one in flight instead of being dropped.
  private var loadID = UUID()

  func loadSmartLists(refresh: Bool = false) async {
    guard !AppConfig.isOffline else { return }
    let instanceId = AppConfig.current.instanceId
    guard !instanceId.isEmpty else { return }

    if SmartListService.isMarkedUnsupported(instanceId: instanceId) {
      isSupported = false
      smartLists = []
      return
    }

    loadID = UUID()
    let currentLoadID = loadID
    isLoading = true
    defer {
      if currentLoadID == loadID {
        isLoading = false
      }
    }

    do {
      let page = try await SmartListService.getSmartLists(unpaged: true)
      guard currentLoadID == loadID else { return }
      smartLists = page.content
      isSupported = true
      SmartListService.recordCapability(instanceId: instanceId, supported: true)
    } catch {
      guard currentLoadID == loadID else { return }
      if case APIError.notFound = error {
        isSupported = false
        smartLists = []
        SmartListService.recordCapability(instanceId: instanceId, supported: false)
      } else if refresh {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

  func removeSmartList(id: String) {
    withAnimation {
      smartLists.removeAll { $0.id == id }
    }
  }
}
