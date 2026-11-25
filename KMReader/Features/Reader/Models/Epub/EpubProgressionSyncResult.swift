import Foundation

enum EpubProgressionSyncResult {
  case available(R2Progression)
  case missing
  case retryableFailure(localProgression: R2Progression?)
  case unavailable
}
