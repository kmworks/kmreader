//
// NotableEntityChipFlows.swift
//

import SwiftUI

struct NotableEntityChipFlows: View {
  enum Target {
    case books
    case series
  }

  let entities: [NotableEntity]
  let target: Target

  private var kinds: [String] {
    let present = Set(entities.map(\.kind))
    return NotableEntity.knownKinds.filter(present.contains)
      + present.filter { !NotableEntity.knownKinds.contains($0) }.sorted()
  }

  var body: some View {
    ForEach(kinds, id: \.self) { kind in
      DetailChipFlow(items: items(kind: kind), collapsedLimit: 6, glass: false)
    }
  }

  private func items(kind: String) -> [DetailChipFlow.Item] {
    entities.filter { $0.kind == kind }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      .map { entity in
        .init(
          title: entity.name,
          systemImage: icon(kind: kind),
          destination: .navigate(destination(for: entity))
        )
      }
  }

  private func destination(for entity: NotableEntity) -> NavDestination {
    switch target {
    case .books:
      return .browseBooksWithNotableEntity(entity: entity)
    case .series:
      return .browseSeriesWithNotableEntity(entity: entity)
    }
  }

  private func icon(kind: String) -> String {
    switch kind {
    case "character":
      return "person"
    case "team":
      return "person.2"
    case "location":
      return "mappin"
    default:
      return "tag"
    }
  }
}
