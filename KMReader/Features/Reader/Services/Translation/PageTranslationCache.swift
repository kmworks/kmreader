import CryptoKit
import Foundation

nonisolated enum PageTranslationCache {
  static let pipelineVersion = 3
  static let variantMarker = ".translated-"

  static func variantFileURL(sourceFileURL: URL, config: PageTranslationConfig) -> URL {
    let key = "\(config.targetLanguage)|\(config.model)|v\(pipelineVersion)"
    let digest = SHA256.hash(data: Data(key.utf8))
    let hash6 = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    let baseName = sourceFileURL.deletingPathExtension().lastPathComponent
    let fileName = "\(baseName)\(variantMarker)\(config.targetLanguage)-\(hash6).png"
    return sourceFileURL.deletingLastPathComponent().appendingPathComponent(fileName)
  }
}
