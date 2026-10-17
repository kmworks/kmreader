//
// PinnedSmartListIds.swift
//
//

import Foundation

/// Client-side pin state for smart lists, keyed by Komga instance. Collections and
/// read lists keep `is_pinned` in GRDB, but smart lists have no local mirror, so
/// their pins live in UserDefaults and stay invisible to the server.
nonisolated struct PinnedSmartListIds: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  /// Instance id -> pinned smart list ids, kept sorted for a stable raw value.
  private(set) var idsByInstance: [String: [String]]

  init(idsByInstance: [String: [String]] = [:]) {
    self.idsByInstance = idsByInstance
  }

  func isPinned(smartListId: String, instanceId: String) -> Bool {
    idsByInstance[instanceId]?.contains(smartListId) ?? false
  }

  mutating func setPinned(_ pinned: Bool, smartListId: String, instanceId: String) {
    var ids = idsByInstance[instanceId] ?? []
    if pinned {
      guard !ids.contains(smartListId) else { return }
      ids.append(smartListId)
      ids.sort()
    } else {
      ids.removeAll { $0 == smartListId }
    }
    idsByInstance[instanceId] = ids.isEmpty ? nil : ids
  }

  /// Pinned lists first, preserving the server's name order inside both partitions.
  func pinnedFirst(_ smartLists: [SmartList], instanceId: String) -> [SmartList] {
    smartLists.filter { isPinned(smartListId: $0.id, instanceId: instanceId) }
      + smartLists.filter { !isPinned(smartListId: $0.id, instanceId: instanceId) }
  }

  var rawValue: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    guard
      let data = try? encoder.encode(idsByInstance),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }

    return json
  }

  init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8), !data.isEmpty else {
      self.idsByInstance = [:]
      return
    }

    if let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
      self.idsByInstance = decoded
    } else {
      self.idsByInstance = [:]
    }
  }
}
