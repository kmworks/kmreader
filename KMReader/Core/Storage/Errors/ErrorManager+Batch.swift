//
// ErrorManager+Batch.swift
//
//

import Foundation

extension ErrorManager {
  func alertBatchFailure(failedCount: Int, totalCount: Int, error: Error?) {
    let summary = String(localized: "batch.failure \(failedCount) \(totalCount)")
    if let error {
      alert(message: "\(summary)\n\(error.localizedDescription)")
    } else {
      alert(message: summary)
    }
  }
}
