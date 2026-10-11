import Foundation

nonisolated struct MangaProviderRequest {
  static let timeoutInterval: TimeInterval = 30

  static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
      group.addTask {
        do {
          let (data, response) = try await URLSession.shared.data(for: request)
          guard let httpResponse = response as? HTTPURLResponse else {
            throw MangaTranslationFailure.invalidResponse
          }
          return (data, httpResponse)
        } catch let error as MangaTranslationFailure {
          throw error
        } catch {
          throw MangaTranslationFailure.network
        }
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(Self.timeoutInterval * 1_000_000_000))
        throw MangaTranslationFailure.timeout
      }
      defer { group.cancelAll() }
      guard let response = try await group.next() else {
        throw MangaTranslationFailure.invalidResponse
      }
      return response
    }
  }
}
