//
// ReadingStatsTimePoint.swift
//
//

import Foundation

nonisolated struct ReadingStatsTimePoint: Codable, Equatable, Sendable, Identifiable {
  let name: String
  let value: Double
  let dateString: String?

  var id: String {
    if let dateString, !dateString.isEmpty {
      return "\(dateString)-\(name)"
    }
    return name
  }

  init(name: String, value: Double, dateString: String? = nil) {
    self.name = name
    self.value = value
    self.dateString = dateString
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case label
    case title
    case key
    case value
    case count
    case hours
    case pagesRead
    case date
    case timestamp
    case time
    case period
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedDate = try container.decodeFirstString(forKeys: [.date, .timestamp, .time, .period])
    dateString = decodedDate
    name = try container.decodeFirstString(forKeys: [.name, .label, .title, .key]) ?? decodedDate ?? "-"
    value = try container.decodeFirstDouble(forKeys: [.value, .hours, .count, .pagesRead]) ?? 0
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(value, forKey: .value)
    try container.encodeIfPresent(dateString, forKey: .date)
  }
}
