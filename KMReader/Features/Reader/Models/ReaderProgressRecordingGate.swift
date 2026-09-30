//
// ReaderProgressRecordingGate.swift
//
//

import Foundation

/// Record Progress After policy for one book within a reader session. The
/// threshold guards the books an accidental open would change the status of:
/// an unread or finished book records nothing until the reader moves that many
/// pages from where the session started. A book already in progress records
/// any move, and a book that has recorded keeps recording, so its progress
/// follows the reader. Opening a book without moving never records.
struct ReaderProgressRecordingGate {
  let wasInProgress: Bool
  private(set) var hasRecorded = false

  init(wasInProgress: Bool) {
    self.wasInProgress = wasInProgress
  }

  /// Whether the reader may record after moving `distance` pages from where
  /// the session started. The book's last page (`completed`) always records,
  /// and `pageCount` clamps the threshold so a short book can still be
  /// finished.
  func allowsRecording(distance: Int, completed: Bool, pageCount: Int?) -> Bool {
    let threshold = AppConfig.progressRecordingThreshold
    guard threshold > 0 else { return true }
    if completed || hasRecorded { return true }

    var requiredDistance = threshold
    if let pageCount, pageCount > 0 {
      requiredDistance = min(requiredDistance, max(0, pageCount - 1))
    }
    if wasInProgress {
      requiredDistance = min(requiredDistance, 1)
    }
    return distance >= requiredDistance
  }

  mutating func markRecorded() {
    hasRecorded = true
  }
}
