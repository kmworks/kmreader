//
// PageSplitMode.swift
//
//

/// Split mode for wide pages
nonisolated enum PageSplitMode: String, Hashable, Codable {
  case none
  case leftHalf
  case rightHalf
}
