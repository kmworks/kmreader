//
// BatchOperationController.swift
//
//

import Foundation

/// Sequential per-item execution shared by selection-mode batch actions.
@MainActor
@Observable
final class BatchOperationController {
  private(set) var completedCount = 0
  private(set) var totalCount = 0
  private(set) var isRunning = false

  func run(
    ids: [String],
    operation: (String) async throws -> Void
  ) async -> BatchOperationOutcome {
    guard !isRunning else {
      return BatchOperationOutcome(succeeded: [], failed: ids, firstError: nil)
    }

    isRunning = true
    completedCount = 0
    totalCount = ids.count
    defer { isRunning = false }

    var succeeded: [String] = []
    var failed: [String] = []
    var firstError: Error?

    for (index, id) in ids.enumerated() {
      do {
        try Task.checkCancellation()
        try await operation(id)
        succeeded.append(id)
      } catch {
        failed.append(id)
        if firstError == nil {
          firstError = error
        }
      }
      completedCount = index + 1

      if Task.isCancelled {
        failed.append(contentsOf: ids.dropFirst(index + 1))
        break
      }
    }

    return BatchOperationOutcome(succeeded: succeeded, failed: failed, firstError: firstError)
  }
}
