import Foundation

/// The async/await download APIs never deliver byte progress to any
/// delegate, and completion-handler tasks bypass delegates entirely, so
/// progress reporting requires a delegate-driven task. The delegate moves
/// the finished file inside the callback (the system deletes it on return)
/// and reports through a stream, keeping no shared mutable state.
nonisolated final class MangaModelDownloader: NSObject {
  enum Event {
    case progress(received: Int64, expected: Int64?)
    case finished(statusCode: Int)
  }

  private let destination: URL
  private let expectedBytes: Int64?
  private let continuation: AsyncThrowingStream<Event, Error>.Continuation

  init(
    destination: URL,
    expectedBytes: Int64?,
    continuation: AsyncThrowingStream<Event, Error>.Continuation
  ) {
    self.destination = destination
    self.expectedBytes = expectedBytes
    self.continuation = continuation
  }

  static func download(
    with request: URLRequest,
    destination: URL,
    expectedBytes: Int64?,
    onProgress: @escaping @Sendable (Int64, Int64?) -> Void
  ) async throws -> Int {
    var continuation: AsyncThrowingStream<Event, Error>.Continuation!
    let events = AsyncThrowingStream<Event, Error> { continuation = $0 }
    let delegate = MangaModelDownloader(
      destination: destination,
      expectedBytes: expectedBytes,
      continuation: continuation
    )
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    session.downloadTask(with: request).resume()

    var lastReport: ContinuousClock.Instant?
    var statusCode = 0
    for try await event in events {
      switch event {
      case .progress(let received, let expected):
        let now = ContinuousClock.now
        let isFinal = expected.map { received >= $0 } ?? false
        if !isFinal, let lastReport, lastReport.duration(to: now) < .milliseconds(100) {
          continue
        }
        lastReport = now
        onProgress(received, expected)
      case .finished(let status):
        statusCode = status
      }
    }
    // A cancelled consumer ends the stream loop without a finished event;
    // surface cancellation instead of a bogus zero status.
    if Task.isCancelled { throw CancellationError() }
    return statusCode
  }
}

extension MangaModelDownloader: URLSessionDownloadDelegate {
  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
    continuation.yield(.progress(received: totalBytesWritten, expected: expected))
  }

  nonisolated func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    do {
      try FileManager.default.moveItem(at: location, to: destination)
      continuation.yield(.finished(statusCode: (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0))
      continuation.finish()
    } catch {
      continuation.finish(throwing: error)
    }
  }

  nonisolated func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      continuation.finish(throwing: error)
    }
  }
}
