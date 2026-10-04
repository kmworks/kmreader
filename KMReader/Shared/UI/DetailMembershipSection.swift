//
// DetailMembershipSection.swift
//
//

import SwiftUI

/// Membership section of detail pages: navigation rows for the entities the
/// page's subject belongs to, collapsing beyond 3 entries behind a
/// Show More/Show Less toggle.
struct DetailMembershipSection: View {
  let title: LocalizedStringKey
  let icon: String
  let items: [DetailMembershipItem]

  @State private var isExpanded = false

  private let collapsedLimit = 3

  private var displayedItems: [DetailMembershipItem] {
    if isExpanded || items.count <= collapsedLimit {
      return items
    }
    return Array(items.prefix(collapsedLimit))
  }

  // Pure display component: loading is hoisted to the parent detail view, so
  // the section renders nothing while empty — an always-present zero-height
  // anchor would collapse the surrounding stack spacing.
  var body: some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
          ForEach(displayedItems) { item in
            NavigationLink(value: item.destination) {
              HStack {
                Label(item.name, systemImage: icon)
                  .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .padding()
              .background(
                LayoutConfig.neutralFillColor,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
              )
              .contentShape(Rectangle())
            }
            .adaptiveButtonStyle(.plain)
          }
        }

        if items.count > collapsedLimit {
          ExpandToggleButton(isExpanded: $isExpanded)
        }
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

extension DetailMembershipSection {
  init(readLists: [SidebarReadListItem]) {
    self.init(
      title: "Read Lists",
      icon: ContentIcon.readList,
      items: readLists.map {
        DetailMembershipItem(
          id: $0.readListId,
          name: $0.name,
          destination: .readListDetail(readListId: $0.readListId)
        )
      }
    )
  }

  init(collections: [SidebarCollectionItem]) {
    self.init(
      title: "Collections",
      icon: ContentIcon.collection,
      items: collections.map {
        DetailMembershipItem(
          id: $0.collectionId,
          name: $0.name,
          destination: .collectionDetail(collectionId: $0.collectionId)
        )
      }
    )
  }
}
