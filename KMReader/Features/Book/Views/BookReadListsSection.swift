//
// BookReadListsSection.swift
//
//

import SwiftUI

struct BookReadListsSection: View {
  let readLists: [SidebarReadListItem]

  @State private var isExpanded = false

  private let collapsedLimit = 3

  private var displayedReadLists: [SidebarReadListItem] {
    if isExpanded || readLists.count <= collapsedLimit {
      return readLists
    }
    return Array(readLists.prefix(collapsedLimit))
  }

  // Pure display component: loading is hoisted to the parent detail view, so
  // the section renders nothing while empty — an always-present zero-height
  // anchor would collapse the surrounding stack spacing.
  var body: some View {
    if !readLists.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("Read Lists")
          .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
          ForEach(displayedReadLists) { readList in
            NavigationLink(value: NavDestination.readListDetail(readListId: readList.readListId)) {
              HStack {
                Label(readList.name, systemImage: ContentIcon.readList)
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

        if readLists.count > collapsedLimit {
          ExpandToggleButton(isExpanded: $isExpanded)
        }
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
