//
// ReadStatusSelectionHelper.swift
//
//

import Foundation

enum ReadStatus: String, Codable, CaseIterable, Sendable {
  case unread = "UNREAD"
  case inProgress = "IN_PROGRESS"
  case read = "READ"

  nonisolated static func fromSeriesCounts(
    booksCount: Int,
    booksReadCount: Int,
    booksInProgressCount: Int
  ) -> ReadStatus {
    if booksCount > 0 && booksReadCount == booksCount {
      return .read
    }
    if booksReadCount > 0 || booksInProgressCount > 0 {
      return .inProgress
    }
    return .unread
  }

  var displayName: String {
    switch self {
    case .read: return String(localized: "readStatus.read")
    case .unread: return String(localized: "readStatus.unread")
    case .inProgress: return String(localized: "readStatus.inProgress")
    }
  }

  /// Base outline names; render sites apply `.symbolVariant(.fill)` for emphasis.
  var icon: String {
    switch self {
    case .read: return "checkmark.circle"
    case .inProgress: return "circle.righthalf.filled"
    case .unread: return "circle"
    }
  }
}

func resolveReadStatusState(
  for status: ReadStatus,
  include: Set<ReadStatus>,
  exclude: Set<ReadStatus>
) -> TriStateSelection {
  if include.contains(status) {
    return .include
  }
  if exclude.contains(status) {
    return .exclude
  }
  return .off
}

func applyReadStatusToggle(
  _ status: ReadStatus,
  include: inout Set<ReadStatus>,
  exclude: inout Set<ReadStatus>
) {
  if include.contains(status) {
    include.remove(status)
    exclude.insert(status)
  } else if exclude.contains(status) {
    exclude.remove(status)
  } else {
    include.insert(status)
  }
}

func buildReadStatusLabel(include: Set<ReadStatus>, exclude: Set<ReadStatus>) -> String? {
  let includeNames = include.map { $0.displayName }.sorted()
  let excludeNames = exclude.map { $0.displayName }.sorted()

  var parts: [String] = []
  if !includeNames.isEmpty {
    parts.append(includeNames.joined(separator: " ∨ "))
  }
  if !excludeNames.isEmpty {
    parts.append("≠ " + excludeNames.joined(separator: " ∨ "))
  }

  return parts.isEmpty ? nil : parts.joined(separator: ", ")
}
