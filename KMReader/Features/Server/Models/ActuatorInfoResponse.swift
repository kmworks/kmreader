//
// ActuatorInfoResponse.swift
//
//

import Foundation

/// `GET /actuator/info`: build/git metadata and host OS. Sections stay
/// optional so a leaner payload still decodes.
nonisolated struct ActuatorInfoResponse: Decodable, Sendable {
  let git: Git?
  let build: Build?
  let os: OperatingSystem?

  struct Git: Decodable, Sendable {
    let branch: String?
    let commit: Commit?

    struct Commit: Decodable, Sendable {
      let id: String?
      let time: String?
    }
  }

  struct Build: Decodable, Sendable {
    let artifact: String?
    let name: String?
    let version: String?
    let group: String?
  }

  struct OperatingSystem: Decodable, Sendable {
    let name: String?
    let version: String?
    let arch: String?
  }
}
