//
// ErrorManager.swift
//
//

import Foundation
import OSLog
import SwiftUI

/// Global error manager for handling and displaying errors across the app
@MainActor
@Observable
class ErrorManager {
  static let shared = ErrorManager()

  var hasAlert: Bool = false
  var currentError: AppError?
  private(set) var notifications: [AppNotification] = []

  private let logger = AppLogger(.notification)

  /// Keeps the exit animation (0.25–0.3s) off the visible toast before it leaves the list.
  private static let removalDelay: TimeInterval = 0.35

  @ObservationIgnored private var lifetimeTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var removalTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var pendingActions: [UUID: PendingAction] = [:]
  /// Plain toasts arriving while an action toast is visible wait here, so a
  /// background event can never hide a pending Undo and let its commit run unseen.
  @ObservationIgnored private var queuedMessages: [(message: String, duration: TimeInterval?)] = []

  private init() {}

  /// Show an alert for an error
  func alert(error: Error) {
    guard shouldShowError(error) else {
      return
    }

    let message = handleError(error)
    guard !message.isEmpty else {
      return
    }

    logger.error("⚠️ Alert: \(message)")

    let appError = AppError(message: message, underlyingError: error)
    currentError = appError
    hasAlert = true
  }

  /// Show an alert with a message
  func alert(message: String) {
    logger.error("⚠️ Alert: \(message)")
    let appError = AppError(message: message, underlyingError: nil)
    currentError = appError
    hasAlert = true
  }

  /// Dismiss the current error alert
  func vanishError() {
    currentError = nil
    hasAlert = false
  }

  /// Show a notification message (non-blocking).
  /// Without an explicit `duration` the lifetime follows the text length:
  /// 3s for short messages, up to 8s for long ones.
  @discardableResult
  func notify(message: String, duration: TimeInterval? = nil) -> UUID {
    enqueue(message: message, actionTitle: nil, duration: duration, commit: nil)
  }

  /// Show a notification with an action button (e.g. Undo). `commit` is deferred work
  /// executed when the toast times out, is superseded, or is swiped away; tapping the
  /// action button runs `cancel` instead. Default lifetime is 5s.
  @discardableResult
  func notify(
    message: String,
    actionTitle: String,
    duration: TimeInterval? = nil,
    commit: @escaping @MainActor () async -> Void,
    cancel: (@MainActor () async -> Void)? = nil
  ) -> UUID {
    enqueue(
      message: message, actionTitle: actionTitle, duration: duration, commit: commit,
      cancel: cancel)
  }

  /// Convenience for the common undo pattern.
  @discardableResult
  func notifyUndo(
    message: String,
    duration: TimeInterval? = nil,
    commit: @escaping @MainActor () async -> Void,
    cancel: (@MainActor () async -> Void)? = nil
  ) -> UUID {
    notify(
      message: message, actionTitle: String(localized: "Undo"), duration: duration,
      commit: commit, cancel: cancel)
  }

  /// Action button tapped: run the cancel closure and dismiss.
  func performAction(id: UUID) {
    if let action = pendingActions.removeValue(forKey: id) {
      Task { await action.cancel() }
    }
    beginExit(id: id, style: .expired)
  }

  /// The toast has animated itself off-screen after a swipe: drop it and settle its commit.
  func dismiss(id: UUID) {
    removeNotification(id: id)
    lifetimeTasks.removeValue(forKey: id)?.cancel()
    removalTasks.removeValue(forKey: id)?.cancel()
    runPendingCommit(id: id)
  }

  // MARK: - Notification Lifecycle

  private func enqueue(
    message: String,
    actionTitle: String?,
    duration: TimeInterval?,
    commit: (@MainActor () async -> Void)?,
    cancel: (@MainActor () async -> Void)? = nil
  ) -> UUID {
    logger.info("📢 Notify: \(message)")
    if actionTitle == nil,
      let active = notifications.last(where: { $0.dismissal == nil }),
      active.actionTitle != nil
    {
      queuedMessages.append((message, duration))
      // No live toast carries this id, so programmatic uses of it are safe no-ops.
      return UUID()
    }
    let delay = duration ?? Self.defaultDuration(for: message, hasAction: actionTitle != nil)
    let notification = AppNotification(
      message: message,
      actionTitle: actionTitle,
      deadline: Date().addingTimeInterval(delay),
      lifetime: delay
    )
    // A newer toast supersedes the visible one, which settles its action immediately.
    if let index = notifications.lastIndex(where: { $0.dismissal == nil }) {
      beginExit(id: notifications[index].id, style: .replaced)
    }
    notifications.append(notification)
    if let commit {
      pendingActions[notification.id] = PendingAction(commit: commit, cancel: cancel)
    }
    let task = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self else { return }
      self.beginExit(id: notification.id, style: .expired)
    }
    lifetimeTasks[notification.id] = task
    return notification.id
  }

  private func beginExit(id: UUID, style: AppNotification.Dismissal) {
    lifetimeTasks.removeValue(forKey: id)?.cancel()
    runPendingCommit(id: id)
    guard let index = notifications.firstIndex(where: { $0.id == id }),
      notifications[index].dismissal == nil
    else { return }
    withAnimation(.appCurve(style == .replaced ? 0.3 : 0.25)) {
      notifications[index].dismissal = style
    }
    scheduleRemoval(id: id)
  }

  private func scheduleRemoval(id: UUID) {
    guard removalTasks[id] == nil else { return }
    let task = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.removalDelay))
      guard !Task.isCancelled, let self else { return }
      self.removeNotification(id: id)
      self.removalTasks.removeValue(forKey: id)
    }
    removalTasks[id] = task
  }

  private func removeNotification(id: UUID) {
    notifications.removeAll { $0.id == id }
    drainQueuedMessages()
  }

  private func drainQueuedMessages() {
    guard notifications.isEmpty, let queued = queuedMessages.first else { return }
    queuedMessages.removeFirst()
    _ = enqueue(message: queued.message, actionTitle: nil, duration: queued.duration, commit: nil)
  }

  private func runPendingCommit(id: UUID) {
    guard let action = pendingActions.removeValue(forKey: id) else { return }
    Task { await action.commit() }
  }

  private static func defaultDuration(for message: String, hasAction: Bool) -> TimeInterval {
    if hasAction { return 5 }
    let readingTime = TimeInterval(message.count) / 14
    guard readingTime > 3 else { return 3 }
    return min(max(readingTime, 5), 8)
  }

  // MARK: - Private Error Handling

  private func handleError(_ error: Error) -> String {
    // Handle APIError
    if let apiError = error as? APIError {
      return apiError.description
    }

    // Handle AppErrorType
    if let appError = error as? AppErrorType {
      return appError.description
    }

    // Pure Swift errors without LocalizedError (e.g. LibArchive.ArchiveError)
    // bridge to a generic message that hides the case name and payload.
    if error.isGenericBridgedSwiftError {
      return String(describing: error)
    }

    // Convert NSError to AppErrorType and handle
    if let nsError = error as NSError? {
      let appError = AppErrorType.from(nsError)
      return appError.description
    }

    return error.localizedDescription
  }

  private func shouldShowError(_ error: Error) -> Bool {
    // Handle AppErrorType
    if let appError = error as? AppErrorType {
      return appError.shouldShow
    }

    // Handle APIError
    if let apiError = error as? APIError {
      // Silently fail offline errors - user is already aware of being offline
      if case .offline = apiError {
        return false
      }

      if case .networkError(let underlyingError, url: _) = apiError {
        // Check if underlying error is cancelled
        if let appError = underlyingError as? AppErrorType,
          case .networkCancelled = appError
        {
          return false
        }
        if let nsError = underlyingError as NSError?,
          nsError.domain == NSURLErrorDomain,
          nsError.code == NSURLErrorCancelled
        {
          return false
        }
      }
    }

    // Convert NSError to AppErrorType and check
    if let nsError = error as NSError? {
      let appError = AppErrorType.from(nsError)
      return appError.shouldShow
    }

    return true
  }
}

struct AppNotification: Identifiable, Equatable {
  enum Dismissal: Equatable {
    /// Timeout or action-button exit.
    case expired
    /// Superseded by a newer toast.
    case replaced
  }

  let id: UUID
  let message: String
  let actionTitle: String?
  let deadline: Date
  /// Total granted lifetime, for rendering the remaining-time ring.
  let lifetime: TimeInterval
  var dismissal: Dismissal?

  init(
    id: UUID = UUID(),
    message: String,
    actionTitle: String? = nil,
    deadline: Date,
    lifetime: TimeInterval,
    dismissal: Dismissal? = nil
  ) {
    self.id = id
    self.message = message
    self.actionTitle = actionTitle
    self.deadline = deadline
    self.lifetime = lifetime
    self.dismissal = dismissal
  }
}

/// Deferred work behind an action toast: `commit` runs when the toast settles
/// without action (timeout, superseded, swiped away), `cancel` when the user
/// taps the action button.
private struct PendingAction {
  let commit: @MainActor () async -> Void
  let cancel: @MainActor () async -> Void

  init(commit: @escaping @MainActor () async -> Void, cancel: (@MainActor () async -> Void)?) {
    self.commit = commit
    self.cancel = cancel ?? {}
  }
}

/// Represents an application error with user-friendly message
struct AppError: Identifiable, CustomStringConvertible {
  let id = UUID()
  let message: String
  let underlyingError: Error?
  let timestamp = Date()

  var description: String {
    message
  }
}
