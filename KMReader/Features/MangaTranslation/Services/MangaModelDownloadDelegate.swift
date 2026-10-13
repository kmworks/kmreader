import Foundation

/// Completion stays with the async download API, so the delegate only
/// forwards byte progress; didFinishDownloadingTo intentionally stays empty.
final class MangaModelDownloadDelegate: NSObject {
  private let expectedBytes: Int64?
  private let onProgress: @Sendable (Int64, Int64?) -> Void

  nonisolated init(expectedBytes: Int64?, onProgress: @escaping @Sendable (Int64, Int64?) -> Void) {
    self.expectedBytes = expectedBytes
    self.onProgress = onProgress
  }
}

extension MangaModelDownloadDelegate: URLSessionDownloadDelegate {
  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
    onProgress(totalBytesWritten, expected)
  }

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
