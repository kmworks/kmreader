//
// SearchCategorySectionView.swift
//
//

import SwiftUI

/// One non-empty category strip in the search overview: a header link showing
/// the category and total match count, a bounded horizontal preview row, and a
/// trailing View All card when more matches exist.
@MainActor
struct SearchCategorySectionView<Content: View>: View {
  let category: BrowseContentType
  let totalCount: Int?
  let showsViewAll: Bool
  let destination: NavDestination
  let itemIds: [String]
  @ViewBuilder let content: () -> Content

  @Environment(\.pushNavDestination) private var pushNavDestination

  #if os(macOS)
    @State private var stripContentFrame: CGRect = .zero
  #endif

  private var bottomPadding: CGFloat {
    LayoutConfig.dashboardSectionBottomPadding(gradientBackground: false)
  }

  /// iOS opens the full category like Dashboard strips (header link or
  /// trailing overscroll); macOS and tvOS have no overscroll trigger, so they
  /// keep an explicit trailing View All card.
  private var showsViewAllCard: Bool {
    #if os(iOS)
      return false
    #else
      return showsViewAll
    #endif
  }

  private var scrollItemIds: [String] {
    showsViewAllCard ? itemIds + ["search-view-all"] : itemIds
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      NavigationLink(value: destination) {
        HStack(spacing: 6) {
          headerTitle
            .font(.title2)
            .bold()
            .fontDesign(.serif)
          Image(systemName: "chevron.right")
            .font(.headline)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
      }
      // Plain chrome: adaptive .plain becomes a card button on tvOS, which
      // boxes section headers instead of leaving them as text links.
      .buttonStyle(.plain)
      .padding(.horizontal)
      .padding(.top, LayoutConfig.dashboardSectionTopPadding)
      #if os(macOS)
        .padding(.leading, 16)
      #endif

      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: LayoutConfig.defaultSpacing) {
            content()
            if showsViewAllCard {
              SearchViewAllCard(destination: destination)
                .id("search-view-all")
            }
          }
          #if os(iOS) || os(tvOS)
            .padding(.top, LayoutConfig.dashboardSectionHeaderSpacing)
            .padding(.bottom, bottomPadding)
          #endif
          #if os(macOS)
            .padding(.leading, 16)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
              stripContentFrame = $0
            }
          #endif
        }
        .contentMargins(.horizontal, LayoutConfig.defaultSpacing, for: .scrollContent)
        .scrollClipDisabled()
        .trailingOverscrollTrigger {
          pushNavDestination(destination)
        }
        #if os(macOS)
          .macHorizontalScrollButtons(
            scrollProxy: proxy,
            itemIds: scrollItemIds,
            contentFrame: stripContentFrame,
            horizontalContentMargin: LayoutConfig.defaultSpacing,
            coverHeight: LayoutConfig.gridCardWidth * CoverAspectRatio.heightToWidth
          )
          .padding(.top, LayoutConfig.dashboardSectionHeaderSpacing)
          .padding(.bottom, bottomPadding)
        #endif
      }
    }
  }

  private var headerTitle: Text {
    guard let totalCount else { return Text(category.displayName) }
    return Text(category.displayName) + Text(verbatim: " · \(totalCount)")
  }
}
