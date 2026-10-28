//
// NativeServerInfo.swift
//

import Foundation

nonisolated struct NativeServerInfo: Decodable, Sendable {
  let version: String
  let gitBranch: String
  let gitCommitId: String

  var actuatorInfo: ActuatorInfoResponse {
    ActuatorInfoResponse(
      git: .init(branch: gitBranch, commit: .init(id: gitCommitId, time: nil)),
      build: .init(artifact: nil, name: nil, version: version, group: nil),
      os: nil
    )
  }
}
