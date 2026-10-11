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

  var cacheKey: String {
    MangaSignature.make([
      "instanceId": instanceId,
      "bookId": pageID.bookId,
      "pageNumber": String(pageID.pageNumber),
      "splitMode": String(describing: splitMode),
      "rotation": String(rotation.rawValue),
      "borderCropMode": borderCropMode.rawValue,
      "sourceSignature": sourceSignature,
      "providerSignature": providerSignature,
      "modelSignature": modelSignature,
    ])
  }
}
