//
// ActuatorHealthResponse.swift
//
//

import Foundation

/// `GET /actuator/health`: overall status plus per-component details (the
/// details are only sent to admins).
nonisolated struct ActuatorHealthResponse: Decodable, Sendable {
  let status: String
  let components: Components?

  struct Components: Decodable, Sendable {
    let diskSpace: DiskSpace?

    struct DiskSpace: Decodable, Sendable {
      let status: String
      let details: Details?

      struct Details: Decodable, Sendable {
        let total: Double?
        let free: Double?
      }
    }
  }
}
