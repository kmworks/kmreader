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
  private var reconnectTask: Task<Void, Never>?
  private var lastEventID: String?
  private var cursorInstanceId: String?

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
    reconnectTask?.cancel()
    reconnectTask = nil
    let instanceId = AppConfig.current.instanceId
    if cursorInstanceId != instanceId {
      lastEventID = nil
      cursorInstanceId = instanceId
    }
    let lastEventID = self.lastEventID
    streamTask = Task.detached(priority: .utility) {
      await SSEService.shared.handleSSEStream(
        url: url, instanceId: instanceId, lastEventID: lastEventID)
    }
    isConnected = true
  }

  func disconnect(notify: Bool = true, resettingCursor: Bool = false) {
    if resettingCursor {
      lastEventID = nil
      cursorInstanceId = nil
    }
    guard isConnected || streamTask != nil || reconnectTask != nil else { return }

    logger.info("🔌 Disconnecting SSE")
    streamTask?.cancel()
    streamTask = nil
    reconnectTask?.cancel()
    reconnectTask = nil
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

  fileprivate func handleSSEStream(url: URL, instanceId: String, lastEventID: String?) async {
    guard isStreamCurrent(url: url, instanceId: instanceId, lastEventID: lastEventID) else {
      return
    }
    var request = URLRequest(url: url)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    if let lastEventID, !lastEventID.isEmpty {
      request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
    }

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
        if isStreamCurrent(url: url, instanceId: instanceId, lastEventID: lastEventID) {
          self.isConnected = false
        }
        scheduleReconnectIfNeeded(url: url, instanceId: instanceId, lastEventID: lastEventID)
        return
      }

      logger.info("✅ SSE connected")

      // Notify user that SSE connected successfully (if notifications enabled)
      if AppConfig.enableSSENotify {
        await ErrorManager.shared.notify(
          message: String(localized: "notification.sse.connected"))
      }

      var currentEventType: String?
      var currentEventID: String?
      var currentData: [String] = []

      for try await line in asyncBytes.lines {
        guard isStreamCurrent(url: url, instanceId: instanceId, lastEventID: lastEventID) else {
          return
        }

        if line.isEmpty {
          if let eventType = currentEventType, !currentData.isEmpty {
            if let currentEventID, !currentEventID.isEmpty,
              cursorInstanceId == instanceId
            {
              self.lastEventID = currentEventID
            }
            await handleSSEEvent(type: eventType, data: currentData.joined(separator: "\n"))
          }
          currentEventType = nil
          currentEventID = nil
          currentData = []
        } else if line.hasPrefix(":") {
          continue
        } else if let (field, value) = Self.parseField(line) {
          switch field {
          case "event":
            currentEventType = value
          case "id":
            currentEventID = value
          case "data":
            currentData.append(value)
          default:
            break
          }
        }
      }

      // Stream ended - connection closed
      logger.warning("SSE stream ended - connection closed")
      scheduleReconnectIfNeeded(url: url, instanceId: instanceId, lastEventID: lastEventID)
    } catch {
      if !Task.isCancelled {
        logger.error("SSE stream error: \(error.localizedDescription)")
        scheduleReconnectIfNeeded(url: url, instanceId: instanceId, lastEventID: lastEventID)
      }
    }
  }

  private func isStreamCurrent(url: URL, instanceId: String, lastEventID: String?) -> Bool {
    guard AppConfig.current.instanceId == instanceId,
      AppConfig.current.serverURL + "/sse/v1/events" == url.absoluteString
    else { return false }
    return cursorInstanceId == instanceId && self.lastEventID == lastEventID
  }

  private func scheduleReconnectIfNeeded(url: URL, instanceId: String, lastEventID: String?) {
    guard isStreamCurrent(url: url, instanceId: instanceId, lastEventID: lastEventID) else {
      return
    }
    isConnected = false
    streamTask = nil
    guard AppConfig.isLoggedIn, AppConfig.enableSSE, !AppConfig.isOffline else { return }
    reconnectTask = Task {
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard !Task.isCancelled, AppConfig.isLoggedIn, !isConnected,
        AppConfig.enableSSE, !AppConfig.isOffline,
        isStreamCurrent(url: url, instanceId: instanceId, lastEventID: lastEventID)
      else { return }
      reconnectTask = nil
      logger.info("Reconnecting SSE")
      connect()
    }
  }

  private static func parseField(_ line: String) -> (field: String, value: String)? {
    guard let separator = line.firstIndex(of: ":") else { return (line, "") }
    let field = String(line[..<separator])
    var value = line[line.index(after: separator)...]
    if value.hasPrefix(" ") {
      value = value.dropFirst()
    }
    return (field, String(value))
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
    await ListProjectionSyncService.shared.scheduleSmartListMembershipSync()
    return true
  }

  private func postReadProgressSeriesDashboardRefresh(data: String) async -> Bool {
    guard stringValue("seriesId", from: data) != nil else { return false }
    await DashboardSectionRefreshNotifier.postReadStatusChanged(
      source: .auto,
      reason: "Remote series read progress changed"
    )
    await ListProjectionSyncService.shared.scheduleSmartListMembershipSync()
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
