//
// RawCodableStore.swift
//
//

import Foundation

nonisolated enum RawCodableStore {
  // RawRepresentable types must provide their own Codable implementation to avoid recursively encoding rawValue.
  static func encode<T: Encodable>(_ value: T) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try? encoder.encode(value)
  }

  static func encodeOptional<T: Encodable>(_ value: T?) -> Data? {
    guard let value else { return nil }
    return encode(value)
  }

  static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
    guard let data else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}
