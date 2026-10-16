import Foundation

nonisolated enum FontFamilyChoice: Hashable, Identifiable, Sendable {
  case publisher
  case system(String)

  static let publisherStorageValue = "__kmreader_publisher_default__"
  static let publisherDisplayValue = String(localized: "Publisher Default")
  static let legacyPublisherValues: Set<String> = [
    "Publisher Default",
    "Verleger-Standard",
    "Par défaut de l'éditeur",
    "出版社デフォルト",
    "출판사 기본값",
    "出版商默认",
    "出版商預設",
    publisherDisplayValue,
  ]

  var id: String { rawValue }

  var rawValue: String {
    switch self {
    case .publisher: return FontFamilyChoice.publisherStorageValue
    case .system(let name): return name
    }
  }

  init(rawValue: String) {
    if rawValue == FontFamilyChoice.publisherStorageValue
      || FontFamilyChoice.legacyPublisherValues.contains(rawValue)
    {
      self = .publisher
    } else {
      self = .system(rawValue)
    }
  }

  var displayName: String {
    switch self {
    case .publisher: return FontFamilyChoice.publisherDisplayValue
    case .system(let name): return name
    }
  }

  var fontName: String? {
    switch self {
    case .publisher: return nil
    case .system(let name): return name
    }
  }
}
