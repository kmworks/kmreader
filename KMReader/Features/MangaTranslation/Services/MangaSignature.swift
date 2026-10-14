import CryptoKit
import Foundation

struct MangaSignature {
  nonisolated static func make(_ values: [String: String]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else {
      return ""
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
