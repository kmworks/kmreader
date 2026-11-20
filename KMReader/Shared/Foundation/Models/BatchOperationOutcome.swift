//
// BatchOperationOutcome.swift
//
//

import Foundation

struct BatchOperationOutcome {
  let succeeded: [String]
  let failed: [String]
  let firstError: Error?

  var totalCount: Int {
    succeeded.count + failed.count
  }
}
