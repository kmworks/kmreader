import Foundation

nonisolated struct MangaTranslationPageKey: Hashable, Codable, Sendable {
  let instanceId: String
  let pageID: ReaderPageID
  let splitMode: PageSplitMode
  let rotation: ReaderRotation
  let borderCropMode: ReaderPageBorderCropMode
  let sourceSignature: String
  let providerSignature: String
  let modelSignature: String

  // Signatures are "<archive sha256>:<inference cache version>"; cache
  // pruning uses the archive prefix to find retired same-page rows.
  var modelArchivePrefix: String {
    modelSignature.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
  }

  var cacheKey: String {
    MangaSignature.make([
      "instanceId": instanceId,
      "bookId": pageID.bookId,
      "pageNumber": String(pageID.pageNumber),
      "splitMode": splitMode.rawValue,
      "rotation": String(rotation.rawValue),
      "borderCropMode": borderCropMode.rawValue,
      "sourceSignature": sourceSignature,
      "providerSignature": providerSignature,
      "modelSignature": modelSignature,
    ])
  }
}
