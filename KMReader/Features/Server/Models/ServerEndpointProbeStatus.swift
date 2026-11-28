//
// ServerEndpointProbeStatus.swift
//

import Foundation

nonisolated enum ServerEndpointProbeStatus: Equatable, Sendable {
  case checking
  case reachable(milliseconds: Int)
  case unauthorized
  case unreachable
}
