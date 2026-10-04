//
// DetailMembershipItem.swift
//
//

import Foundation

/// Row model for DetailMembershipSection: a named entity the page's subject
/// belongs to (a book's read lists, a series' collections).
struct DetailMembershipItem: Identifiable {
  let id: String
  let name: String
  let destination: NavDestination
}
