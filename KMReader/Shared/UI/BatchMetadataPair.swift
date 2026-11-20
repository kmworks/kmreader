//
// BatchMetadataPair.swift
//
//

import Foundation

struct BatchMetadataPair: Identifiable, Equatable {
  let id = UUID()
  var first: String
  var second: String
}
