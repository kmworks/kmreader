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
    guard AppConfig.serverTrackerCapability.shouldQuery(instanceId: instanceId) else {
      isSupported = false
      checkedInstanceId = instanceId
      return
    }

    do {
      preferences = try await TrackerService.getPreferences()
      record(supported: true)
      isSupported = true
      checkedInstanceId = instanceId
    } catch {
      isSupported = false
      if case APIError.notFound = error {
        record(supported: false)
        checkedInstanceId = instanceId
      } else {
        checkedInstanceId = nil
        preferences = nil
      }
    }
  }

  func allows(libraryId: String) -> Bool {
    guard let preferences else { return isSupported }
    return preferences.libraries.isEmpty || preferences.libraries.contains(libraryId)
  }

  func updatePreferences(_ preferences: TrackerPreferences) {
    self.preferences = preferences
  }

  func refreshCompleted(supported: Bool) {
    record(supported: supported)
    isSupported = supported
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

  private func record(supported: Bool) {
    var capability = AppConfig.serverTrackerCapability
    capability.record(instanceId: AppConfig.current.instanceId, supported: supported)
    AppConfig.serverTrackerCapability = capability
  }
}
