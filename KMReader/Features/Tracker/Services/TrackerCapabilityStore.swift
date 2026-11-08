//
// TrackerCapabilityStore.swift
//

import Foundation

@MainActor
@Observable
final class TrackerCapabilityStore {
  static let shared = TrackerCapabilityStore()

  private(set) var isSupported = false
  private(set) var preferences: TrackerPreferences?
  private var checkedInstanceId: String?

  private init() {}

  func refresh() async {
    let instanceId = AppConfig.current.instanceId
    guard !AppConfig.isOffline, !instanceId.isEmpty else {
      clear()
      return
    }
    guard checkedInstanceId != instanceId else { return }
    preferences = nil
    isSupported = false
    guard ServerProfileService.supports(.trackers, instanceId: instanceId) else {
      checkedInstanceId = instanceId
      return
    }

    do {
      preferences = try await TrackerService.getPreferences()
      isSupported = true
      checkedInstanceId = instanceId
    } catch {
      checkedInstanceId = nil
      preferences = nil
    }
  }

  func allows(libraryId: String) -> Bool {
    guard let preferences else { return isSupported }
    return preferences.libraries.isEmpty || preferences.libraries.contains(libraryId)
  }

  func updatePreferences(_ preferences: TrackerPreferences) {
    self.preferences = preferences
  }

  /// A tracker screen loaded its data, so the endpoints answer.
  func refreshCompleted() {
    isSupported = true
    checkedInstanceId = AppConfig.current.instanceId
  }

  func invalidate() {
    checkedInstanceId = nil
    clear()
  }

  private func clear() {
    checkedInstanceId = nil
    isSupported = false
    preferences = nil
  }
}
