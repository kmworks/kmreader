//
// APIClient.swift
//
//

import Foundation
import OSLog

struct DownloadProgressUserInfo {
  nonisolated static let urlKey = "url"
  nonisolated static let itemKey = "item"
  nonisolated static let receivedKey = "received"
  nonisolated static let expectedKey = "expected"
}

extension Notification.Name {
  nonisolated static let fileDownloadProgress = Notification.Name("fileDownloadProgress")
}

nonisolated final class APIClient: Sendable {
  static let shared = APIClient()
  private typealias ProgressHandler = @Sendable (_ received: Int64, _ expected: Int64?) -> Void

  private let logger = AppLogger(.api)

  private let userAgent: String

  enum RequestCategory {
    case general
    case download
    case auth
  }

  private actor OfflineFailureTracker {
    private var consecutiveFailures = 0

    func recordSuccess() {
      consecutiveFailures = 0
    }

    func shouldSwitchOffline(isAuth: Bool) -> Bool {
      consecutiveFailures += 1
      let threshold = isAuth ? 1 : 3
      return consecutiveFailures >= threshold
    }
  }

  private let offlineFailureTracker = OfflineFailureTracker()

  private let sharedSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(
      memoryCapacity: 50 * 1024 * 1024,  // 50MB memory cache
      diskCapacity: 0,
      diskPath: nil
    )
    configuration.requestCachePolicy = .useProtocolCachePolicy
    return URLSession(configuration: configuration)
  }()

  private init() {
    self.userAgent = AppConfig.userAgent
  }

  private func currentSession() -> URLSession {
    sharedSession
  }

  func setServer(url: String) {
    // Uphold Current.serverURL's no-trailing-slash invariant: this is the
    // only post-init write path (Current's inits normalize their own).
    AppConfig.current.serverURL = Current.normalizeServerURL(url)
  }

  func setAuthToken(_ token: String?) {
    AppConfig.current.authToken = token ?? ""
  }

  // MARK: - Temporary Request (doesn't modify global state)

  /// Execute a temporary request without modifying global APIClient state
  /// This is useful for login validation where we don't want to affect the current server connection
  func requestTemporary<T: Decodable>(
    serverURL: String,
    path: String,
    method: String = "GET",
    authToken: String? = nil,
    body: Data? = nil,
    queryItems: [URLQueryItem]? = nil,
    headers: [String: String]? = nil
  ) async throws -> T {
    try await performLoginTemporary(
      serverURL: serverURL,
      path: path,
      method: method,
      authToken: authToken,
      body: body,
      queryItems: queryItems,
      headers: headers
    )
  }

  /// Execute a login request specifically to establish session cookies
  func performLogin(
    serverURL: String,
    path: String,
    method: String = "GET",
    authToken: String,
    authMethod: AuthenticationMethod = .basicAuth,
    queryItems: [URLQueryItem]? = nil,
    headers: [String: String]? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> User {
    let request = try buildLoginRequest(
      serverURL: serverURL,
      path: path,
      method: method,
      queryItems: queryItems,
      headers: headers,
      authToken: authToken,
      authMethod: authMethod,
      useSessionToken: false,
      timeout: timeout
    )

    let (data, httpResponse) = try await executeRequest(
      request, session: currentSession(), isTemporary: false, requestCategory: .auth)
    return try decodeResponse(data: data, httpResponse: httpResponse, request: request)
  }

  /// Execute a stateless login request for validation
  func performLoginTemporary<T: Decodable>(
    serverURL: String,
    path: String,
    method: String = "GET",
    authToken: String? = nil,
    authMethod: AuthenticationMethod = .basicAuth,
    body: Data? = nil,
    queryItems: [URLQueryItem]? = nil,
    headers: [String: String]? = nil
  ) async throws -> T {
    let request = try buildLoginRequest(
      serverURL: serverURL,
      path: path,
      method: method,
      body: body,
      queryItems: queryItems,
      headers: headers,
      authToken: authToken,
      authMethod: authMethod,
      useSessionToken: false
    )

    // Execute request with temporary session (ephemeral, no persistent cookies)
    let tempSession = URLSession(
      configuration: {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return config
      }())

    let (data, httpResponse) = try await executeRequest(
      request, session: tempSession, isTemporary: true, requestCategory: .auth)

    return try decodeResponse(data: data, httpResponse: httpResponse, request: request)
  }

  // MARK: - Private Helpers

  private func decodeResponse<T: Decodable>(
    data: Data,
    httpResponse: HTTPURLResponse,
    request: URLRequest
  ) throws -> T {
    // Handle 204 No Content responses - skip JSON decoding
    if httpResponse.statusCode == 204 || data.isEmpty {
      if T.self == EmptyResponse.self, let value = EmptyResponse() as? T {
        return value
      } else if data.isEmpty {
        let urlString = request.url?.absoluteString ?? ""
        logger.warning("⚠️ Empty response data from \(urlString)")
        throw APIError.decodingError(
          AppErrorType.missingRequiredData(message: "Empty response data"),
          url: urlString,
          response: nil
        )
      }
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      if let date = APIClientDateParser.parse(value) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid date format: \(value)"
      )
    }

    do {
      return try decoder.decode(T.self, from: data)
    } catch let decodingError as DecodingError {
      // Provide detailed decoding error information
      switch decodingError {
      case .keyNotFound(let key, let context):
        let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
        logger.error("❌ Missing key '\(key.stringValue)' at path: \(path)")
      case .typeMismatch(let type, let context):
        let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
        logger.error("❌ Type mismatch for type '\(String(describing: type))' at path: \(path)")
      case .valueNotFound(let type, let context):
        let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
        logger.error("❌ Value not found for type '\(String(describing: type))' at path: \(path)")
      case .dataCorrupted(let context):
        logger.error("❌ Data corrupted: \(context.debugDescription)")
      @unknown default:
        logger.error("❌ Unknown decoding error: \(decodingError.localizedDescription)")
      }

      let responseBody = String(data: data, encoding: .utf8)
      if let jsonString = responseBody {
        let truncated = String(jsonString.prefix(1000))
        logger.debug("Response data: \(truncated)")
      }

      let urlString = request.url?.absoluteString ?? ""
      throw APIError.decodingError(decodingError, url: urlString, response: responseBody)
    } catch {
      let urlString = request.url?.absoluteString ?? ""
      let errorDesc = error.localizedDescription
      logger.error("❌ Decoding error for \(urlString): \(errorDesc)")

      let responseBody = String(data: data, encoding: .utf8)
      if let jsonString = responseBody {
        let truncated = String(jsonString.prefix(1000))
        logger.debug("Response data: \(truncated)")
      }

      throw APIError.decodingError(error, url: urlString, response: responseBody)
    }
  }

  private func buildRequest(
    path: String,
    method: String,
    body: Data? = nil,
    queryItems: [URLQueryItem]? = nil,
    headers: [String: String]? = nil,
    timeout: TimeInterval? = nil,
    category: RequestCategory = .general
  ) throws -> URLRequest {
    guard var urlComponents = URLComponents(string: AppConfig.current.serverURL + path) else {
      throw APIError.invalidURL
    }

    if let queryItems = queryItems {
      urlComponents.queryItems = queryItems
    }

    guard let url = urlComponents.url else {
      throw APIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = resolveTimeout(timeout, category: category)

    configureDefaultHeaders(&request, body: body, headers: headers)

    Self.applyAuthHeaders(to: &request)

    return request
  }

  /// Add auth headers based on the authentication method.
  ///
  /// Always attach the session token when one exists. For API key
  /// instances, also always attach the key: Komga prefers the session
  /// while it is valid (and skips key re-authentication for
  /// API-key-created sessions), and falls back to the key when the
  /// session expired, which also rotates a fresh session token back.
  /// Password logins keep relying on the session/cookies only, since
  /// per-request Basic authentication would flood the server auth log.
  ///
  /// Shared by every outbound request (JSON API, URL-based resource
  /// downloads, SSE) so all channels authenticate from the same single
  /// credential source instead of relying on implicit cookie storage.
  nonisolated static func applyAuthHeaders(to request: inout URLRequest) {
    let authMethod = AppConfig.current.authMethod
    let authToken = AppConfig.current.authToken

    guard !authToken.isEmpty else { return }

    let sessionToken = AppConfig.current.sessionToken
    if !sessionToken.isEmpty {
      request.setValue(sessionToken, forHTTPHeaderField: "X-Auth-Token")
    }
    if authMethod == .apiKey {
      request.setValue(authToken, forHTTPHeaderField: "X-API-Key")
    }
  }

  private func resolveTimeout(
    _ timeout: TimeInterval?,
    category: RequestCategory
  ) -> TimeInterval {
    timeout ?? defaultTimeout(for: category)
  }

  private func defaultTimeout(for category: RequestCategory) -> TimeInterval {
    switch category {
    case .general:
      return AppConfig.requestTimeout
    case .download:
      return AppConfig.downloadTimeout
    case .auth:
      return AppConfig.authTimeout
    }
  }

  private func buildLoginRequest(
    serverURL: String? = nil,
    path: String,
    method: String,
    body: Data? = nil,
    queryItems: [URLQueryItem]? = nil,
    headers: [String: String]? = nil,
    authToken: String? = nil,
    authMethod: AuthenticationMethod? = nil,
    useSessionToken: Bool = true,
    timeout: TimeInterval? = nil,
    category: RequestCategory = .auth
  ) throws -> URLRequest {
    let baseURL = (serverURL ?? AppConfig.current.serverURL).trimmingCharacters(
      in: .whitespacesAndNewlines)
    var urlString = baseURL
    if !urlString.hasSuffix("/") {
      urlString += "/"
    }
    let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    urlString += trimmedPath

    guard var urlComponents = URLComponents(string: urlString) else {
      throw APIError.invalidURL
    }

    if let queryItems = queryItems {
      urlComponents.queryItems = queryItems
    }

    guard let url = urlComponents.url else {
      throw APIError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = resolveTimeout(timeout, category: category)

    configureDefaultHeaders(&request, body: body, headers: headers)

    // Add auth header based on the authentication method
    if let token = authToken, !token.isEmpty {
      let method = authMethod ?? AppConfig.current.authMethod

      // Common logic: Prioritize session token if available and requested
      let sessionToken = AppConfig.current.sessionToken
      if useSessionToken && !sessionToken.isEmpty {
        request.setValue(sessionToken, forHTTPHeaderField: "X-Auth-Token")
      } else {
        // Fallback to specific auth headers if session token is not used or available
        switch method {
        case .basicAuth:
          request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        case .apiKey:
          request.setValue(token, forHTTPHeaderField: "X-API-Key")
        }
      }
    }

    return request
  }

  private func buildRequest(
    url: URL,
    method: String,
    body: Data? = nil,
    headers: [String: String]? = nil,
    category: RequestCategory = .general
  ) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = resolveTimeout(nil, category: category)
    configureDefaultHeaders(&request, body: body, headers: headers)
    Self.applyAuthHeaders(to: &request)
    return request
  }

  private func configureDefaultHeaders(
    _ request: inout URLRequest,
    body: Data?,
    headers: [String: String]?
  ) {
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

    if body != nil && request.value(forHTTPHeaderField: "Content-Type") == nil {
      request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    headers?.forEach { key, value in
      request.setValue(value, forHTTPHeaderField: key)
    }
  }

  /// Actor to synchronize concurrent re-login attempts
  private actor ReLoginActor {
    private var reLoginTask: Task<(Data, HTTPURLResponse), Error>?

    func getReLoginTask(
      perform: @Sendable @escaping () async throws -> (Data, HTTPURLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
      // If there's already a re-login in progress, wait for it
      if let task = reLoginTask {
        return try await task.value
      }

      // Start a new re-login task
      let task = Task {
        defer { reLoginTask = nil }
        return try await perform()
      }

      reLoginTask = task
      return try await task.value
    }
  }

  private let reLoginActor = ReLoginActor()

  private func executeRequest(
    _ request: URLRequest,
    session: URLSession? = nil,
    isTemporary: Bool = false,
    requestCategory: RequestCategory = .general,
    retryCount: Int = 0,
    maxRetryCount: Int? = nil,
    onProgress: ProgressHandler? = nil
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? ""
    let prefix = isTemporary ? "[TEMP] " : ""
    logger.info("📡 \(prefix)\(method) \(urlString)")

    let startTime = Date()
    let sessionToUse = session ?? currentSession()
    let effectiveMaxRetryCount = maxRetryCount ?? AppConfig.apiRetryCount

    struct FetchResult {
      let data: Data
      let response: HTTPURLResponse
      let expectedBytes: Int64?
    }

    func fetchWithProgress(
      _ onProgress: @escaping ProgressHandler
    ) async throws -> FetchResult {
      actor ProgressState {
        let onProgress: ProgressHandler
        let urlString: String
        var data = Data()
        var response: HTTPURLResponse?
        var expectedBytes: Int64?
        var receivedBytes: Int64 = 0
        var continuation: CheckedContinuation<FetchResult, Error>?
        var lastUpdate = Date.distantPast
        let updateInterval: TimeInterval = 0.1

        init(
          onProgress: @escaping ProgressHandler,
          urlString: String
        ) {
          self.onProgress = onProgress
          self.urlString = urlString
        }

        func setContinuation(_ continuation: CheckedContinuation<FetchResult, Error>) {
          self.continuation = continuation
        }

        func fail(_ error: Error) {
          guard let continuation else { return }
          self.continuation = nil
          continuation.resume(throwing: error)
        }

        func handleResponse(_ httpResponse: HTTPURLResponse) {
          response = httpResponse
          let expectedLength = httpResponse.expectedContentLength
          expectedBytes = expectedLength > 0 ? expectedLength : nil
          onProgress(0, expectedBytes)
        }

        func handleData(_ chunk: Data) {
          data.append(chunk)
          receivedBytes += Int64(chunk.count)

          let now = Date()
          guard now.timeIntervalSince(lastUpdate) >= updateInterval else { return }
          lastUpdate = now
          onProgress(receivedBytes, expectedBytes)
        }

        func handleComplete(_ error: Error?) {
          guard continuation != nil else { return }
          if let error {
            fail(error)
            return
          }
          guard let response else {
            fail(APIError.invalidResponse(url: urlString))
            return
          }

          onProgress(receivedBytes, expectedBytes)
          let result = FetchResult(data: data, response: response, expectedBytes: expectedBytes)
          continuation?.resume(returning: result)
          continuation = nil
        }
      }

      final class ProgressDelegate: NSObject, URLSessionDataDelegate {
        let state: ProgressState
        let urlString: String

        init(state: ProgressState, urlString: String) {
          self.state = state
          self.urlString = urlString
        }

        func urlSession(
          _ session: URLSession,
          dataTask: URLSessionDataTask,
          didReceive response: URLResponse,
          completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
          guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            Task { await state.fail(APIError.invalidResponse(url: urlString)) }
            return
          }

          completionHandler(.allow)
          Task { await state.handleResponse(httpResponse) }
        }

        func urlSession(
          _ session: URLSession,
          dataTask: URLSessionDataTask,
          didReceive data: Data
        ) {
          Task { await state.handleData(data) }
        }

        func urlSession(
          _ session: URLSession,
          task: URLSessionTask,
          didCompleteWithError error: Error?
        ) {
          defer {
            session.finishTasksAndInvalidate()
          }

          Task { await state.handleComplete(error) }
        }
      }

      logger.debug("Streaming download started: url=\(urlString)")
      let onProgressHandler: ProgressHandler = {
        received, expected in
        Task { @MainActor in
          onProgress(received, expected)
        }
      }
      let state = ProgressState(onProgress: onProgressHandler, urlString: urlString)
      let delegate = ProgressDelegate(state: state, urlString: urlString)
      let delegateQueue = OperationQueue()
      delegateQueue.maxConcurrentOperationCount = 1
      let progressSession = URLSession(
        configuration: sessionToUse.configuration,
        delegate: delegate,
        delegateQueue: delegateQueue
      )

      return try await withCheckedThrowingContinuation { continuation in
        Task {
          await state.setContinuation(continuation)
          let task = progressSession.dataTask(with: request)
          task.resume()
        }
      }
    }

    func fetch() async throws -> FetchResult {
      if let onProgress {
        let result = try await fetchWithProgress(onProgress)
        if let expectedBytes = result.expectedBytes {
          logger.debug(
            "Streaming download finished: bytes=\(result.data.count) expected=\(expectedBytes) url=\(urlString)"
          )
        } else {
          logger.debug(
            "Streaming download finished: bytes=\(result.data.count) expected=unknown url=\(urlString)"
          )
        }
        return result
      }

      let (data, response) = try await sessionToUse.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        logger.error("❌ Invalid response from \(urlString)")
        throw APIError.invalidResponse(url: urlString)
      }

      return FetchResult(data: data, response: httpResponse, expectedBytes: nil)
    }

    do {
      let result = try await fetch()
      let duration = Date().timeIntervalSince(startTime)
      let data = result.data
      let httpResponse = result.response
      let expectedBytes = result.expectedBytes

      let statusEmoji = (200...299).contains(httpResponse.statusCode) ? "✅" : "❌"
      let durationMs = String(format: "%.2f", duration * 1000)

      if let sessionToken = httpResponse.value(forHTTPHeaderField: "X-Auth-Token") {
        if AppConfig.current.sessionToken != sessionToken {
          AppConfig.current.sessionToken = sessionToken
        }
      }

      logger.info(
        "\(statusEmoji) \(prefix)\(httpResponse.statusCode) \(method) \(urlString) (\(durationMs)ms)"
      )

      guard (200...299).contains(httpResponse.statusCode) else {
        if httpResponse.statusCode == 401 && retryCount == 0 && !isTemporary
          && AppConfig.current.authMethod != .apiKey
        {
          let token = AppConfig.current.authToken
          if !token.isEmpty {
            logger.info("🔒 Unauthorized, attempting re-login to refresh session...")

            do {
              let loginRequest = try buildLoginRequest(
                path: "/api/v2/users/me",
                method: "GET",
                queryItems: [URLQueryItem(name: "remember-me", value: "true")],
                headers: ["X-Auth-Token": ""],
                authToken: token,
                useSessionToken: false
              )

              _ = try await reLoginActor.getReLoginTask { [weak self] in
                guard let self = self else {
                  throw APIError.networkError(
                    AppErrorType.missingRequiredData(message: "APIClient deallocated"),
                    url: urlString
                  )
                }
                return try await self.executeRequest(
                  loginRequest,
                  session: sessionToUse,
                  isTemporary: false,
                  requestCategory: .auth,
                  retryCount: 1,
                  maxRetryCount: maxRetryCount
                )
              }

              logger.info("✅ Re-login successful, retrying original request...")
              if let onProgress {
                onProgress(0, expectedBytes)
              }
              return try await executeRequest(
                request,
                session: sessionToUse,
                isTemporary: false,
                requestCategory: requestCategory,
                retryCount: 1,
                maxRetryCount: maxRetryCount,
                onProgress: onProgress
              )
            } catch {
              logger.error("❌ Re-login failed: \(error.localizedDescription)")
            }
          }
        }

        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        let responseBody = String(data: data, encoding: .utf8)
        let requestBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }

        switch httpResponse.statusCode {
        case 400:
          logger.warning("🔒 Bad Request: \(urlString)")
          throw APIError.badRequest(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 401:
          logger.warning("🔒 Unauthorized: \(urlString)")
          throw APIError.unauthorized(url: urlString)
        case 403:
          logger.warning("🔒 Forbidden: \(urlString)")
          throw APIError.forbidden(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 404:
          logger.warning("🔒 Not Found: \(urlString)")
          throw APIError.notFound(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 429:
          logger.warning("🔒 Too Many Requests: \(urlString)")
          throw APIError.tooManyRequests(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 500...599:
          if retryCount < effectiveMaxRetryCount {
            logger.warning(
              "⚠️ Server error, retrying (\(retryCount + 1)/\(effectiveMaxRetryCount)): \(httpResponse.statusCode)"
            )
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return try await executeRequest(
              request,
              session: session,
              isTemporary: isTemporary,
              requestCategory: requestCategory,
              retryCount: retryCount + 1,
              maxRetryCount: maxRetryCount,
              onProgress: onProgress
            )
          }

          logger.error("❌ Server Error \(httpResponse.statusCode): \(errorMessage)")
          throw APIError.serverError(
            code: httpResponse.statusCode, message: errorMessage, url: urlString,
            response: responseBody, request: requestBody)
        default:
          logger.error("❌ HTTP \(httpResponse.statusCode): \(errorMessage)")
          throw APIError.httpError(
            code: httpResponse.statusCode, message: errorMessage, url: urlString,
            response: responseBody, request: requestBody)
        }
      }

      await offlineFailureTracker.recordSuccess()
      return (data, httpResponse)
    } catch let error as APIError {
      throw error
    } catch let appError as AppErrorType {
      logger.error("❌ Network error for \(urlString): \(appError.description)")
      let shouldHandleOffline = !isTemporary && requestCategory != .download
      if shouldHandleOffline {
        await handleNetworkError(appError, requestCategory: requestCategory)
      }
      throw APIError.networkError(appError, url: urlString)
    } catch let nsError as NSError where nsError.domain == NSURLErrorDomain {
      let appError = AppErrorType.from(nsError)
      logger.error("❌ Network error for \(urlString): \(appError.description)")
      let shouldHandleOffline = !isTemporary && requestCategory != .download
      if shouldHandleOffline {
        await handleNetworkError(nsError, requestCategory: requestCategory)
      }
      throw APIError.networkError(appError, url: urlString)
    } catch {
      if retryCount < effectiveMaxRetryCount && !(error is CancellationError) {
        logger.warning(
          "⚠️ Request failed, retrying (\(retryCount + 1)/\(effectiveMaxRetryCount)): \(error.localizedDescription)"
        )
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return try await executeRequest(
          request,
          session: session,
          isTemporary: isTemporary,
          requestCategory: requestCategory,
          retryCount: retryCount + 1,
          maxRetryCount: maxRetryCount,
          onProgress: onProgress
        )
      }

      logger.error("❌ Network error for \(urlString): \(error.localizedDescription)")
      let shouldHandleOffline = !isTemporary && requestCategory != .download
      if shouldHandleOffline {
        await handleNetworkError(error, requestCategory: requestCategory)
      }
      throw APIError.networkError(error, url: urlString)
    }
  }

  private struct DownloadFileResult {
    let response: HTTPURLResponse
    let temporaryURL: URL
    let expectedBytes: Int64?
    let receivedBytes: Int64
  }

  private func executeDownloadRequest(
    _ request: URLRequest,
    destinationURL: URL,
    session: URLSession? = nil,
    isTemporary: Bool = false,
    requestCategory: RequestCategory = .download,
    retryCount: Int = 0,
    maxRetryCount: Int? = nil,
    onProgress: ProgressHandler? = nil
  ) async throws -> HTTPURLResponse {
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? ""
    let prefix = isTemporary ? "[TEMP] " : ""
    logger.info("📡 \(prefix)\(method) \(urlString)")

    let startTime = Date()
    let sessionToUse = session ?? currentSession()
    let effectiveMaxRetryCount = maxRetryCount ?? AppConfig.apiRetryCount
    let temporaryURL = makeTemporaryDownloadURL(for: destinationURL)

    actor DownloadState {
      let onProgress: ProgressHandler?
      let urlString: String
      var response: HTTPURLResponse?
      var expectedBytes: Int64?
      var receivedBytes: Int64 = 0
      var downloadedFileURL: URL?
      var downloadedFileError: Error?
      var didReceiveFile = false
      var didComplete = false
      var completionError: Error?
      var continuation: CheckedContinuation<DownloadFileResult, Error>?
      var lastUpdate = Date.distantPast
      let updateInterval: TimeInterval = 0.1

      init(onProgress: ProgressHandler?, urlString: String) {
        self.onProgress = onProgress
        self.urlString = urlString
      }

      func setContinuation(_ continuation: CheckedContinuation<DownloadFileResult, Error>) {
        self.continuation = continuation
      }

      func handleProgress(received: Int64, expected: Int64) {
        receivedBytes = received
        if expected > 0 {
          expectedBytes = expected
        }

        let now = Date()
        guard now.timeIntervalSince(lastUpdate) >= updateInterval else { return }
        lastUpdate = now
        onProgress?(receivedBytes, expectedBytes)
      }

      func handleDownloadedFile(_ fileURL: URL?, error: Error?) {
        didReceiveFile = true
        downloadedFileURL = fileURL
        downloadedFileError = error
        finishIfReady()
      }

      func handleComplete(_ error: Error?, response: HTTPURLResponse?) {
        didComplete = true
        completionError = error
        if let response {
          self.response = response
          let expectedLength = response.expectedContentLength
          if expectedLength > 0 {
            expectedBytes = expectedLength
          }
        }
        finishIfReady()
      }

      private func finishIfReady() {
        guard let continuation else { return }
        guard didComplete else { return }

        if let completionError {
          self.continuation = nil
          continuation.resume(throwing: completionError)
          return
        }

        guard didReceiveFile else { return }

        if let downloadedFileError {
          self.continuation = nil
          continuation.resume(throwing: downloadedFileError)
          return
        }

        guard let response else {
          self.continuation = nil
          continuation.resume(throwing: APIError.invalidResponse(url: urlString))
          return
        }

        guard let downloadedFileURL else {
          self.continuation = nil
          continuation.resume(
            throwing: AppErrorType.missingRequiredData(message: "Missing downloaded file.")
          )
          return
        }

        onProgress?(receivedBytes, expectedBytes)
        self.continuation = nil
        continuation.resume(
          returning: DownloadFileResult(
            response: response,
            temporaryURL: downloadedFileURL,
            expectedBytes: expectedBytes,
            receivedBytes: receivedBytes
          )
        )
      }
    }

    final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
      let state: DownloadState
      let urlString: String
      let temporaryURL: URL

      init(state: DownloadState, urlString: String, temporaryURL: URL) {
        self.state = state
        self.urlString = urlString
        self.temporaryURL = temporaryURL
      }

      func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
      ) {
        let moveError: Error?
        do {
          let directory = temporaryURL.deletingLastPathComponent()
          if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
              at: directory,
              withIntermediateDirectories: true
            )
          }
          if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try FileManager.default.removeItem(at: temporaryURL)
          }
          try FileManager.default.moveItem(at: location, to: temporaryURL)
          moveError = nil
        } catch {
          moveError = error
        }

        Task {
          await state.handleDownloadedFile(moveError == nil ? temporaryURL : nil, error: moveError)
        }
      }

      func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
      ) {
        Task {
          await state.handleProgress(
            received: totalBytesWritten,
            expected: totalBytesExpectedToWrite
          )
        }
      }

      func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
      ) {
        defer {
          session.finishTasksAndInvalidate()
        }

        let response = task.response as? HTTPURLResponse
        Task { await state.handleComplete(error, response: response) }
      }
    }

    do {
      logger.debug("Streaming file download started: url=\(urlString)")
      let state = DownloadState(onProgress: onProgress, urlString: urlString)
      let delegate = DownloadDelegate(
        state: state,
        urlString: urlString,
        temporaryURL: temporaryURL
      )
      let delegateQueue = OperationQueue()
      delegateQueue.maxConcurrentOperationCount = 1
      let downloadSession = URLSession(
        configuration: sessionToUse.configuration,
        delegate: delegate,
        delegateQueue: delegateQueue
      )

      let result = try await withCheckedThrowingContinuation { continuation in
        Task {
          await state.setContinuation(continuation)
          let task = downloadSession.downloadTask(with: request)
          task.resume()
        }
      }

      let duration = Date().timeIntervalSince(startTime)
      let httpResponse = result.response
      let statusEmoji = (200...299).contains(httpResponse.statusCode) ? "✅" : "❌"
      let durationMs = String(format: "%.2f", duration * 1000)

      if let sessionToken = httpResponse.value(forHTTPHeaderField: "X-Auth-Token") {
        if AppConfig.current.sessionToken != sessionToken {
          AppConfig.current.sessionToken = sessionToken
        }
      }

      logger.info(
        "\(statusEmoji) \(prefix)\(httpResponse.statusCode) \(method) \(urlString) (\(durationMs)ms)"
      )

      guard (200...299).contains(httpResponse.statusCode) else {
        let responseBody = try? String(contentsOf: result.temporaryURL, encoding: .utf8)
        try? FileManager.default.removeItem(at: result.temporaryURL)

        if httpResponse.statusCode == 401 && retryCount == 0 && !isTemporary
          && AppConfig.current.authMethod != .apiKey
        {
          let token = AppConfig.current.authToken
          if !token.isEmpty {
            logger.info("🔒 Unauthorized, attempting re-login to refresh session...")
            do {
              let loginRequest = try buildLoginRequest(
                path: "/api/v2/users/me",
                method: "GET",
                queryItems: [URLQueryItem(name: "remember-me", value: "true")],
                headers: ["X-Auth-Token": ""],
                authToken: token,
                useSessionToken: false
              )

              _ = try await reLoginActor.getReLoginTask { [weak self] in
                guard let self = self else {
                  throw APIError.networkError(
                    AppErrorType.missingRequiredData(message: "APIClient deallocated"),
                    url: urlString
                  )
                }
                return try await self.executeRequest(
                  loginRequest,
                  session: sessionToUse,
                  isTemporary: false,
                  requestCategory: .auth,
                  retryCount: 1,
                  maxRetryCount: maxRetryCount
                )
              }

              logger.info("✅ Re-login successful, retrying original file download...")
              onProgress?(0, result.expectedBytes)
              return try await executeDownloadRequest(
                request,
                destinationURL: destinationURL,
                session: sessionToUse,
                isTemporary: false,
                requestCategory: requestCategory,
                retryCount: 1,
                maxRetryCount: maxRetryCount,
                onProgress: onProgress
              )
            } catch {
              logger.error("❌ Re-login failed: \(error.localizedDescription)")
            }
          }
        }

        let errorMessage = responseBody ?? "Unknown error"
        let requestBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }

        switch httpResponse.statusCode {
        case 400:
          throw APIError.badRequest(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 401:
          throw APIError.unauthorized(url: urlString)
        case 403:
          throw APIError.forbidden(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 404:
          throw APIError.notFound(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 429:
          throw APIError.tooManyRequests(
            message: errorMessage, url: urlString, response: responseBody, request: requestBody)
        case 500...599:
          if retryCount < effectiveMaxRetryCount {
            logger.warning(
              "⚠️ Server error, retrying (\(retryCount + 1)/\(effectiveMaxRetryCount)): \(httpResponse.statusCode)"
            )
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return try await executeDownloadRequest(
              request,
              destinationURL: destinationURL,
              session: session,
              isTemporary: isTemporary,
              requestCategory: requestCategory,
              retryCount: retryCount + 1,
              maxRetryCount: maxRetryCount,
              onProgress: onProgress
            )
          }
          throw APIError.serverError(
            code: httpResponse.statusCode, message: errorMessage, url: urlString,
            response: responseBody, request: requestBody)
        default:
          throw APIError.httpError(
            code: httpResponse.statusCode, message: errorMessage, url: urlString,
            response: responseBody, request: requestBody)
        }
      }

      let destinationDir = destinationURL.deletingLastPathComponent()
      if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try FileManager.default.createDirectory(
          at: destinationDir,
          withIntermediateDirectories: true
        )
      }
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
      }
      try FileManager.default.moveItem(at: result.temporaryURL, to: destinationURL)

      let dataSize = ByteCountFormatter.string(
        fromByteCount: result.receivedBytes,
        countStyle: .binary
      )
      logger.info("\(httpResponse.statusCode) \(method) \(urlString) [\(dataSize)]")

      await offlineFailureTracker.recordSuccess()
      return httpResponse
    } catch let error as APIError {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw error
    } catch let appError as AppErrorType {
      try? FileManager.default.removeItem(at: temporaryURL)
      logger.error("❌ Network error for \(urlString): \(appError.description)")
      let shouldHandleOffline = !isTemporary && requestCategory != .download
      if shouldHandleOffline {
        await handleNetworkError(appError, requestCategory: requestCategory)
      }
      throw APIError.networkError(appError, url: urlString)
    } catch let nsError as NSError where nsError.domain == NSURLErrorDomain {
      try? FileManager.default.removeItem(at: temporaryURL)
      let appError = AppErrorType.from(nsError)
      logger.error("❌ Network error for \(urlString): \(appError.description)")
      let shouldHandleOffline = !isTemporary && requestCategory != .download
      if shouldHandleOffline {
        await handleNetworkError(nsError, requestCategory: requestCategory)
      }
      throw APIError.networkError(appError, url: urlString)
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      if retryCount < effectiveMaxRetryCount && !(error is CancellationError) {
        logger.warning(
          "⚠️ File download failed, retrying (\(retryCount + 1)/\(effectiveMaxRetryCount)): \(error.localizedDescription)"
        )
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return try await executeDownloadRequest(
          request,
          destinationURL: destinationURL,
          session: session,
          isTemporary: isTemporary,
          requestCategory: requestCategory,
          retryCount: retryCount + 1,
          maxRetryCount: maxRetryCount,
          onProgress: onProgress
        )
      }

      logger.error("❌ Network error for \(urlString): \(error.localizedDescription)")
      let shouldHandleOffline = !isTemporary && requestCategory != .download
      if shouldHandleOffline {
        await handleNetworkError(error, requestCategory: requestCategory)
      }
      throw APIError.networkError(error, url: urlString)
    }
  }

  private func handleNetworkError(
    _ error: Error,
    requestCategory: RequestCategory
  ) async {
    // Only switch to offline mode if not already offline
    guard !AppConfig.isOffline else { return }

    // Identify if the error is a network connectivity issue
    let isConnectivityIssue: Bool
    if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet,
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorResourceUnavailable:
        isConnectivityIssue = true
      default:
        isConnectivityIssue = false
      }
    } else if let appError = error as? AppErrorType {
      switch appError {
      case .networkUnavailable, .networkTimeout:
        isConnectivityIssue = true
      default:
        isConnectivityIssue = false
      }
    } else {
      isConnectivityIssue = false
    }

    if isConnectivityIssue {
      let shouldSwitch = await offlineFailureTracker.shouldSwitchOffline(
        isAuth: requestCategory == .auth
      )
      guard shouldSwitch else { return }
      logger.info("🔌 Network issue detected, automatically switching to offline mode")
      guard !AppConfig.isOffline else { return }
      AppConfig.enterAutoOfflineMode()
      await SSEService.shared.disconnect()
      await ErrorManager.shared.notify(
        message: String(localized: "notification.automaticOfflineMode"))
    }
  }

  // MARK: - Offline Mode Check

  /// Throws APIError.offline if app is in offline mode
  /// This check is bypassed for login/authentication requests
  private func throwIfOffline() throws {
    if AppConfig.isOffline {
      throw APIError.offline
    }
  }

  func request<T: Decodable>(
    path: String,
    method: String = "GET",
    body: Data? = nil,
    queryItems: [URLQueryItem]? = nil,
    headers: [String: String]? = nil,
    bypassOfflineCheck: Bool = false,
    timeout: TimeInterval? = nil,
    maxRetryCount: Int? = nil,
    category: RequestCategory = .general
  ) async throws -> T {
    if !bypassOfflineCheck {
      try throwIfOffline()
    }

    let urlRequest = try buildRequest(
      path: path,
      method: method,
      body: body,
      queryItems: queryItems,
      headers: headers,
      timeout: timeout,
      category: category
    )
    let (data, httpResponse) = try await executeRequest(
      urlRequest,
      requestCategory: category,
      maxRetryCount: maxRetryCount
    )

    return try decodeResponse(data: data, httpResponse: httpResponse, request: urlRequest)
  }

  func requestOptional<T: Decodable>(
    path: String,
    method: String = "GET",
    body: Data? = nil,
    queryItems: [URLQueryItem]? = nil,
    headers: [String: String]? = nil,
    category: RequestCategory = .general
  ) async throws -> T? {
    try throwIfOffline()

    let urlRequest = try buildRequest(
      path: path,
      method: method,
      body: body,
      queryItems: queryItems,
      headers: headers,
      category: category
    )
    let (data, httpResponse) = try await executeRequest(urlRequest, requestCategory: category)

    if httpResponse.statusCode == 204 || data.isEmpty {
      return nil
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      let responseBody = String(data: data, encoding: .utf8)
      let urlString = urlRequest.url?.absoluteString ?? ""
      throw APIError.decodingError(error, url: urlString, response: responseBody)
    }
  }

  func requestData(
    path: String,
    method: String = "GET",
    headers: [String: String]? = nil
  ) async throws -> (data: Data, contentType: String?, suggestedFilename: String?) {
    try throwIfOffline()

    let urlRequest = try buildRequest(
      path: path, method: method, headers: headers, category: .download)
    let (data, httpResponse) = try await executeRequest(urlRequest, requestCategory: .download)

    return logAndExtractDataResponse(data: data, response: httpResponse, request: urlRequest)
  }

  func requestFileWithProgress(
    path: String,
    progressKey: String,
    destinationURL: URL,
    method: String = "GET",
    headers: [String: String]? = nil
  ) async throws -> (contentType: String?, suggestedFilename: String?) {
    try throwIfOffline()

    let urlRequest = try buildRequest(
      path: path,
      method: method,
      headers: headers,
      category: .download
    )
    let urlString = urlRequest.url?.absoluteString ?? ""
    let httpResponse = try await executeDownloadRequest(
      urlRequest,
      destinationURL: destinationURL,
      requestCategory: .download,
      onProgress: { received, expected in
        Task { @MainActor in
          NotificationCenter.default.post(
            name: .fileDownloadProgress,
            object: nil,
            userInfo: [
              DownloadProgressUserInfo.urlKey: urlString,
              DownloadProgressUserInfo.itemKey: progressKey,
              DownloadProgressUserInfo.receivedKey: received,
              DownloadProgressUserInfo.expectedKey: expected as Any,
            ]
          )
        }
      }
    )

    return (
      httpResponse.value(forHTTPHeaderField: "Content-Type"),
      filenameFromContentDisposition(httpResponse.value(forHTTPHeaderField: "Content-Disposition"))
    )
  }

  func requestData(
    url: URL,
    method: String = "GET",
    headers: [String: String]? = nil
  ) async throws -> (data: Data, contentType: String?, suggestedFilename: String?) {
    try throwIfOffline()

    let urlRequest = buildRequest(url: url, method: method, headers: headers, category: .download)
    let (data, httpResponse) = try await executeRequest(urlRequest, requestCategory: .download)
    return logAndExtractDataResponse(data: data, response: httpResponse, request: urlRequest)
  }

  private func logAndExtractDataResponse(
    data: Data,
    response: HTTPURLResponse,
    request: URLRequest
  ) -> (data: Data, contentType: String?, suggestedFilename: String?) {
    let contentType = response.value(forHTTPHeaderField: "Content-Type")
    let suggestedFilename = filenameFromContentDisposition(
      response.value(forHTTPHeaderField: "Content-Disposition"))

    let dataSize = ByteCountFormatter.string(
      fromByteCount: Int64(data.count), countStyle: .binary)
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? ""
    logger.info("\(response.statusCode) \(method) \(urlString) [\(dataSize)]")

    return (data, contentType, suggestedFilename)
  }

  private func filenameFromContentDisposition(_ header: String?) -> String? {
    guard let header = header else { return nil }
    let parts = header.split(separator: ";")

    for part in parts {
      let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
      let lowercased = trimmed.lowercased()

      if lowercased.hasPrefix("filename*=") {
        let value = trimmed.dropFirst("filename*=".count)
        let components = value.split(
          separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        if components.count == 3 {
          let encodedFileName = String(components[2])
          return encodedFileName.removingPercentEncoding
        }
      } else if lowercased.hasPrefix("filename=") {
        var fileName = trimmed.dropFirst("filename=".count)
        if fileName.hasPrefix("\""), fileName.hasSuffix("\"") {
          fileName = fileName.dropFirst().dropLast()
        }
        return String(fileName)
      }
    }

    return nil
  }

  private func makeTemporaryDownloadURL(for destinationURL: URL) -> URL {
    let directory = destinationURL.deletingLastPathComponent()
    let fileName = destinationURL.lastPathComponent
    return directory.appendingPathComponent(".\(fileName).\(UUID().uuidString).download")
  }
}

private enum APIClientDateParser {
  nonisolated static func parse(_ value: String) -> Date? {
    if let date = makeISO8601WithFractional().date(from: value) {
      return date
    }
    if let date = makeISO8601Basic().date(from: value) {
      return date
    }
    if let date = makeLocalFormatterWithFractional().date(from: value) {
      return date
    }
    return makeLocalFormatter().date(from: value)
  }

  nonisolated private static func makeISO8601WithFractional() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  nonisolated private static func makeISO8601Basic() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }

  nonisolated private static func makeLocalFormatterWithFractional() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    return formatter
  }

  nonisolated private static func makeLocalFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter
  }
}
