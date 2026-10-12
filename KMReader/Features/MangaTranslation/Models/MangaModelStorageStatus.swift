import Foundation

nonisolated struct MangaModelStorageStatus: Equatable, Sendable {
  let packageExists: Bool
  let compiledExists: Bool
  let packageBytes: Int64
  let compiledBytes: Int64
  let downloadBytes: Int64

  var totalBytes: Int64 { packageBytes + compiledBytes + downloadBytes }
}
