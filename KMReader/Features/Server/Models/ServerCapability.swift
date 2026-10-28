//
// ServerCapability.swift
//

import Foundation

nonisolated struct ServerCapability: Equatable, RawRepresentable, Sendable {
  typealias RawValue = String

  struct Record: Codable, Equatable, Sendable {
    var supported: Bool
    var checkedAt: Date
  }

  var recordsByInstance: [String: Record]

  init(recordsByInstance: [String: Record] = [:]) {
    self.recordsByInstance = recordsByInstance
  }

  func shouldQuery(instanceId: String, now: Date = Date()) -> Bool {
    guard let record = recordsByInstance[instanceId] else { return true }
    return record.supported || now.timeIntervalSince(record.checkedAt) >= 24 * 60 * 60
  }

  mutating func record(instanceId: String, supported: Bool, checkedAt: Date = Date()) {
    if supported, recordsByInstance[instanceId]?.supported == true { return }
    recordsByInstance[instanceId] = Record(supported: supported, checkedAt: checkedAt)
  }

  var rawValue: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(recordsByInstance),
      let json = String(data: data, encoding: .utf8)
    else { return "{}" }
    return json
  }

  init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8), !data.isEmpty else {
      self.init()
      return
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.init(recordsByInstance: (try? decoder.decode([String: Record].self, from: data)) ?? [:])
  }
}
