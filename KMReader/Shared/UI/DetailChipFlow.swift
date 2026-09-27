//
// DetailChipFlow.swift
//
//

import Flow
import SwiftUI

/// Flow of tappable chips for detail pages — the hero creator row
/// (publisher + authors) as well as the genre / tag / link flows below the
/// summary. Long flows collapse behind a trailing "+N" chip that expands in
/// place. Alignment follows `detailHeroCentered`: centered inside the hero,
/// leading in the sections below.
struct DetailChipFlow: View {
  struct Item: Hashable {
    let title: String
    let systemImage: String?
    let destination: Destination
  }

  enum Destination: Hashable {
    case navigate(NavDestination)
    case external(URL)
  }

  let items: [Item]
  let collapsedLimit: Int
  let glass: Bool

  @State private var isExpanded = false

  @Environment(\.detailHeroCentered) private var heroCentered

  init(items: [Item], collapsedLimit: Int = 6, glass: Bool = true) {
    self.items = items
    self.collapsedLimit = collapsedLimit
    self.glass = glass
  }

  var body: some View {
    if !items.isEmpty {
      if heroCentered {
        HFlow(
          horizontalAlignment: .center,
          verticalAlignment: .center,
          horizontalSpacing: 8,
          verticalSpacing: 8
        ) {
          chips
        }
      } else {
        HFlow(itemSpacing: 8) {
          chips
        }
      }
    }
  }

  @ViewBuilder
  private var chips: some View {
    ForEach(displayedItems, id: \.self) { item in
      chipView(for: item)
    }
    if !isExpanded && items.count > collapsedLimit {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          isExpanded = true
        }
      } label: {
        Text("+\(items.count - collapsedLimit)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background {
            Capsule()
              .strokeBorder(Color.secondary.opacity(0.3))
          }
          .contentShape(Capsule())
      }
      .adaptiveButtonStyle(.plain)
    }
  }

  @ViewBuilder
  private func chipView(for item: Item) -> some View {
    switch item.destination {
    case .navigate(let destination):
      NavigationLink(value: destination) {
        DetailChip(item.title, systemImage: item.systemImage, glass: glass)
      }
      .adaptiveButtonStyle(.plain)
    case .external(let url):
      Link(destination: url) {
        DetailChip(item.title, systemImage: item.systemImage, glass: glass)
      }
      .adaptiveButtonStyle(.plain)
    }
  }

  private var displayedItems: [Item] {
    if isExpanded || items.count <= collapsedLimit {
      return items
    }

    return Array(items.prefix(collapsedLimit))
  }
}
