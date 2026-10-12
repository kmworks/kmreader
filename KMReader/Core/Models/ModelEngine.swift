import Foundation

nonisolated struct ModelEngine: RawRepresentable, Hashable, Codable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    rawValue = try container.decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var isValid: Bool {
    ModelPackageManifest.isValidIdentifier(rawValue)
  }

  static let rtDetrV2 = ModelEngine(rawValue: "rt_detr_v2")
  static let mangaOCRTransformer = ModelEngine(rawValue: "manga_ocr_transformer")
  static let yolo11nSeg = ModelEngine(rawValue: "yolo11n_seg")
  static let mangaOCRMobile = ModelEngine(rawValue: "manga_ocr_mobile")
}
