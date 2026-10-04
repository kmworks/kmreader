//
// SeriesCollectionsSection.swift
//
//

import SwiftUI

struct SeriesCollectionsSection: View {
  let collections: [SidebarCollectionItem]

  @State private var isExpanded = false

  private let collapsedLimit = 3

  private var displayedCollections: [SidebarCollectionItem] {
    if isExpanded || collections.count <= collapsedLimit {
      return collections
    }
    return Array(collections.prefix(collapsedLimit))
  }

  // Pure display component: loading is hoisted to the parent detail view, so
  // the section renders nothing while empty — an always-present zero-height
  // anchor would collapse the surrounding stack spacing.
  var body: some View {
    if !collections.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Collections")
          .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
          ForEach(displayedCollections) { collection in
            NavigationLink(
              value: NavDestination.collectionDetail(collectionId: collection.collectionId)
            ) {
              HStack {
                Label(collection.name, systemImage: ContentIcon.collection)
                  .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .padding()
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(16)
              .contentShape(Rectangle())
            }.adaptiveButtonStyle(.plain)
          }
        }

        if collections.count > collapsedLimit {
          ExpandToggleButton(isExpanded: $isExpanded)
        }
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
