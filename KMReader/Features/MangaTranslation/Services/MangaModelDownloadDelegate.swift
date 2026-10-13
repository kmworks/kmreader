import Foundation

/// The async/await download APIs never deliver byte progress to any
/// delegate, and completion-handler tasks bypass delegates entirely, so
/// progress reporting requires a delegate-driven task. The delegate moves
/// the finished file inside the callback (the system deletes it on return)
/// and resumes the awaiting caller.
nonisolated final class MangaModelDownloadDelegate: NSObject {
  private let destination: URL
  private let expectedBytes: Int64?
  private let onProgress: @Sendable (Int64, Int64?) -> Void
  // Written once before the task resumes, then only touched on the serial
  // delegate queue, which orders every callback after that write.
  private let continuationBox = ContinuationBox()

  private final class ContinuationBox {
    var continuation: CheckedContinuation<URLResponse, Error>?
  }

  init(
    destination: URL,
    expectedBytes: Int64?,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void
  ) {
    self.destination = destination
    self.expectedBytes = expectedBytes
    self.onProgress = onProgress
  }

  func download(with request: URLRequest) async throws -> URLResponse {
    let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    return try await withCheckedThrowingContinuation { continuation in
      continuationBox.continuation = continuation
      session.downloadTask(with: request).resume()
    }
  }

  private func finish(_ result: Result<URLResponse, Error>) {
    let continuation = continuationBox.continuation
    continuationBox.continuation = nil
    continuation?.resume(with: result)
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
  ) {
    do {
      try FileManager.default.moveItem(at: location, to: destination)
      guard let response = downloadTask.response else {
        throw MangaTranslationFailure.modelPreparation
      }
      finish(.success(response))
    } catch {
      finish(.failure(error))
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      finish(.failure(error))
    }
  }
}
