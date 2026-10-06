//
// ServerStatsCapability.swift
//
//

import Foundation

/// Per-instance record of whether the server exposes the kmrs-private library
/// and server stats endpoints, so unsupported servers (Komga, older kmrs)
/// skip the doomed request after one probe.
nonisolated struct ServerStatsCapability: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  struct Record: Codable, Equatable, Sendable {
    var supported: Bool
    var checkedAt: Date
  }

  var recordsByInstance: [String: Record]

  init(recordsByInstance: [String: Record] = [:]) {
    self.recordsByInstance = recordsByInstance
  }

  func record(instanceId: String) -> Record? {
    recordsByInstance[instanceId]
  }

  mutating func upsert(instanceId: String, supported: Bool, checkedAt: Date) {
    recordsByInstance[instanceId] = Record(supported: supported, checkedAt: checkedAt)
  }

  var rawValue: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    guard
      let data = try? encoder.encode(recordsByInstance),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }

    return json
  }

  init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8), !data.isEmpty else {
      self.recordsByInstance = [:]
      return
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    if let decoded = try? decoder.decode([String: Record].self, from: data) {
      self.recordsByInstance = decoded
    } else {
      self.recordsByInstance = [:]
    }
  }
}
