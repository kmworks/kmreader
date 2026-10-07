//
// ActuatorScheduledTasksResponse.swift
//
//

import Foundation

/// `GET /actuator/scheduledtasks` (admin only). kmrs reports fixed-rate
/// registrations only; the cron/fixedDelay/custom groups stay empty.
nonisolated struct ActuatorScheduledTasksResponse: Decodable, Sendable {
  let fixedRate: [ScheduledTask]

  struct ScheduledTask: Decodable, Sendable, Identifiable {
    let runnable: Runnable
    /// Milliseconds; equals `interval` for kmrs fixed-rate tasks.
    let initialDelay: Double
    /// Milliseconds.
    let interval: Double

    var id: String { runnable.target }

    struct Runnable: Decodable, Sendable {
      let target: String
    }
  }
}
