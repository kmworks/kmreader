//
// SSEService.swift
//
//

import Foundation
import OSLog

extension Notification.Name {
  static let sseEventReceived = Notification.Name("SSEEventReceived")
}

struct SSEEventInfo: Sendable {
  let type: SSEEventType
  let data: String
}

@globalActor
actor SSEService {
  static let shared = SSEService()

  private let logger = AppLogger(.sse)

  private var isConnected = false
  private var streamTask: Task<Void, Never>?

  var connected: Bool {
    isConnected
  }

  func connect() {
    guard !isConnected else {
      logger.debug("SSE already connected")
      return
    }

    guard !AppConfig.isOffline else {
      logger.debug("SSE connection skipped: app is offline")
      return
    }

    guard AppConfig.enableSSE else {
      logger.debug("SSE is disabled by user preference")
      return
    }

    guard !AppConfig.current.serverURL.isEmpty, !AppConfig.current.authToken.isEmpty else {
      logger.warning("Cannot connect SSE: missing server URL or auth token")
      return
    }

    guard let url = URL(string: AppConfig.current.serverURL + "/sse/v1/events") else {
      logger.error("Invalid SSE URL: \(AppConfig.current.serverURL)/sse/v1/events")
      return
    }

    logger.info("🔌 Connecting to SSE: \(url.absoluteString)")
    streamTask?.cancel()
    streamTask = Task.detached(priority: .utility) {
      await SSEService.shared.handleSSEStream(url: url)
    }
    isConnected = true
  }

  func disconnect(notify: Bool = true) {
    guard isConnected else { return }

    logger.info("🔌 Disconnecting SSE")
    streamTask?.cancel()
    streamTask = nil
    isConnected = false

    // Clear task queue status when disconnecting
    AppConfig.taskQueueStatus = TaskQueueSSEDto()

    // Notify user that SSE disconnected (if notifications enabled)
    if notify && AppConfig.enableSSENotify {
      Task { @MainActor in
        ErrorManager.shared.notify(message: String(localized: "notification.sse.disconnected"))
      }
    }
  }

  fileprivate func handleSSEStream(url: URL) async {
    var request = URLRequest(url: url)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")

    // Authenticate from the same single credential source as every other
    // outbound request: the SSE endpoint is not covered by cookies under
    // stateless API-key auth (and session cookies are memory-only), so an
    // explicit X-Auth-Token / X-API-Key header is required.
    APIClient.applyAuthHeaders(to: &request)

    do {
      let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

      guard let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        logger.error("SSE connection failed: \(response)")
        self.isConnected = false
        return
      }

      logger.info("✅ SSE connected")

      // Notify user that SSE connected successfully (if notifications enabled)
      if AppConfig.enableSSENotify {
        await ErrorManager.shared.notify(
          message: String(localized: "notification.sse.connected"))
      }

      var lineBuffer = ""
      var currentEventType: String?
      var currentData: String?

      for try await byte in asyncBytes {
        if Task.isCancelled {
          break
        }

        let character = Character(UnicodeScalar(byte))

        if character == "\n" {
          // Process complete line
          let line = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
          lineBuffer = ""

          if line.isEmpty {
            // Empty line indicates end of message
            if let eventType = currentEventType, let data = currentData {
              await handleSSEEvent(type: eventType, data: data)
            }
            currentEventType = nil
            currentData = nil
          } else if line.hasPrefix(":") {
            // SSE comment line (heartbeat) - ignore but confirms connection is alive
          } else if line.hasPrefix("event:") {
            currentEventType = String(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
          } else if line.hasPrefix("data:") {
            let data = String(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
            if currentData == nil {
              currentData = data
            } else {
              // Multi-line data
              currentData! += "\n" + data
            }
          }
          // Ignore id: and retry: lines
        } else {
          lineBuffer.append(character)
        }
      }

      // Stream ended - connection closed
      logger.warning("SSE stream ended - connection closed")
      self.isConnected = false

      // Attempt to reconnect if still logged in
      if AppConfig.isLoggedIn && AppConfig.enableSSE && !AppConfig.isOffline && !Task.isCancelled {
        Task {
          try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
          if AppConfig.isLoggedIn && !isConnected && AppConfig.enableSSE && !AppConfig.isOffline {
            logger.info("Reconnecting SSE after stream ended")
            self.connect()
          }
        }
      }
    } catch {
      if !Task.isCancelled {
        logger.error("SSE stream error: \(error.localizedDescription)")
        self.isConnected = false

        // Attempt to reconnect after a delay
        if AppConfig.isLoggedIn && AppConfig.enableSSE && !AppConfig.isOffline {
          Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
            if AppConfig.isLoggedIn && !isConnected && AppConfig.enableSSE && !AppConfig.isOffline {
              logger.info("Reconnecting SSE after error")
              self.connect()
            }
          }
        }
      }
    }
  }

  private func handleSSEEvent(type: String, data: String) async {
    logger.debug("SSE event received: \(type), data: \(data)")

    guard let eventType = SSEEventType(rawValue: type) else {
      logger.debug("Unknown SSE event type: \(type)")
      return
    }

    switch eventType {
    case .taskQueueStatus:
      handleTaskQueueStatus(data: data)
    case .sessionExpired:
      broadcastNotification(type: eventType, data: data)
    default:
      guard AppConfig.enableSSEAutoRefresh else { return }
      await handleSSEAutoRefreshEvent(eventType, data: data)
    }
  }

  private func handleSSEAutoRefreshEvent(_ eventType: SSEEventType, data: String) async {
    switch eventType {
    case .seriesAdded, .seriesChanged, .seriesDeleted:
      guard await postSeriesDashboardRefresh(data: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
    case .bookAdded, .bookChanged, .bookDeleted, .bookImported:
      guard await postBookDashboardRefresh(data: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
    case .collectionAdded, .collectionChanged, .collectionDeleted:
      guard await handleCollectionProjectionSync(data: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
    case .readListAdded, .readListChanged, .readListDeleted:
      guard await handleReadListProjectionSync(data: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
    case .smartListAdded, .smartListChanged, .smartListDeleted:
      guard await handleSmartListProjectionSync(data: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
    case .smartListThumbnailChanged:
      guard let smartListId = stringValue("smartListId", from: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
      try? await ThumbnailCache.refreshThumbnail(id: smartListId, type: .smartList)
    case .readProgressChanged, .readProgressDeleted:
      guard await postReadProgressDashboardRefresh(data: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
    case .readProgressSeriesChanged, .readProgressSeriesDeleted:
      guard await postReadProgressSeriesDashboardRefresh(data: data) else {
        broadcastNotification(type: eventType, data: data)
        return
      }
    default:
      broadcastNotification(type: eventType, data: data)
    }
  }

  private func handleTaskQueueStatus(data: String) {
    guard let dto = TaskQueueSSEDto(rawValue: data) else { return }

    let previousStatus = AppConfig.taskQueueStatus
    guard previousStatus != dto else { return }

    AppConfig.taskQueueStatus = dto
    broadcastNotification(type: .taskQueueStatus, data: data)

    if previousStatus.count > 0 && dto.count == 0 && AppConfig.enableSSENotify {
      Task { @MainActor in
        ErrorManager.shared.notify(
          message: String(localized: "notification.sse.tasksFinished"))
      }
    }
  }

  private func broadcastNotification(type: SSEEventType, data: String) {
    Task { @MainActor in
      NotificationCenter.default.post(
        name: .sseEventReceived,
        object: nil,
        userInfo: ["info": SSEEventInfo(type: type, data: data)]
      )
    }
  }

  private func postSeriesDashboardRefresh(data: String) async -> Bool {
    guard stringValue("seriesId", from: data) != nil else { return false }
    await DashboardSectionRefreshNotifier.postSeriesContentChanged(
      source: .auto,
      reason: "Remote series changed"
    )
    return true
  }

  private func postBookDashboardRefresh(data: String) async -> Bool {
    guard
      stringValue("bookId", from: data) != nil,
      stringValue("seriesId", from: data) != nil
    else { return false }

    await DashboardSectionRefreshNotifier.post(
      sections: DashboardSectionRefreshNotifier.bookContentSections
        .union(DashboardSectionRefreshNotifier.seriesContentSections),
      source: .auto,
      reason: "Remote book changed"
    )
    return true
  }

  /// Remote collection/read-list changes have no dashboard section to refresh;
  /// the projection syncs debounced through its own service instead.
  private func handleCollectionProjectionSync(data: String) async -> Bool {
    guard let collectionId = stringValue("collectionId", from: data) else { return false }
    await ListProjectionSyncService.shared.scheduleCollectionSync(collectionId: collectionId)
    return true
  }

  private func handleReadListProjectionSync(data: String) async -> Bool {
    guard let readListId = stringValue("readListId", from: data) else { return false }
    await ListProjectionSyncService.shared.scheduleReadListSync(readListId: readListId)
    return true
  }

  private func handleSmartListProjectionSync(data: String) async -> Bool {
    guard let smartListId = stringValue("smartListId", from: data) else { return false }
    await ListProjectionSyncService.shared.scheduleSmartListSync(smartListId: smartListId)
    return true
  }

  private func postReadProgressDashboardRefresh(data: String) async -> Bool {
    guard stringValue("bookId", from: data) != nil else { return false }
    await DashboardSectionRefreshNotifier.postReadStatusChanged(
      source: .auto,
      reason: "Remote read progress changed"
    )
    return true
  }

  private func postReadProgressSeriesDashboardRefresh(data: String) async -> Bool {
    guard stringValue("seriesId", from: data) != nil else { return false }
    await DashboardSectionRefreshNotifier.postReadStatusChanged(
      source: .auto,
      reason: "Remote series read progress changed"
    )
    return true
  }

  private func stringValue(_ key: String, from data: String) -> String? {
    guard
      let object = jsonObject(from: data),
      let value = object[key] as? String,
      !value.isEmpty
    else { return nil }

    return value
  }

  private func jsonObject(from data: String) -> [String: Any]? {
    guard
      let payload = data.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    else { return nil }

    return object
  }
}
