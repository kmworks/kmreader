//
// EntityPickerItem.swift
//
//

import Foundation

/// Row model for EntityPickerSheet: a named entity that the target may already
/// belong to.
struct EntityPickerItem: Identifiable {
  let id: String
  let name: String
  let alreadyIn: Bool
}
