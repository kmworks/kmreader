//
// DashboardSectionLayout.swift
//
//

import SwiftUI

/// Shared dashboard section chrome: gradient band, header navigation link,
/// and the horizontal card strip. Owns the band's vertical rhythm so every
/// section reads the same. Callers skip rendering for empty sections: loads
/// live in the central view model, not in view lifetimes.
@MainActor
struct DashboardSectionLayout<Content: View>: View {
  let section: DashboardSection
  let destination: NavDestination
  let showsCardKindMenu: Bool
  let itemIds: [String]
  @ViewBuilder let content: () -> Content

  @Environment(\.pushNavDestination) private var pushNavDestination

  @AppStorage("showDashboardSectionGradientBackground")
  private var showGradientBackground: Bool =
    AppConfig.showDashboardSectionGradientBackground

  #if os(macOS)
    @AppStorage("dashboard") private var dashboard: DashboardConfiguration = DashboardConfiguration()

    /// Scroll-content frame in global coordinates; the macOS scroll arrows
    /// derive the real scroll position from it.
    @State private var stripContentFrame: CGRect = .zero

    /// Grid cards carry metadata below the cover, so the arrows center on the
    /// cover block at the card top; horizontal cards are cover-tall already.
    private var scrollArrowsCoverHeight: CGFloat? {
      let kind = dashboard.cardKind(for: section)
      guard kind != .horizontal else { return nil }
      return kind.cardWidth * CoverAspectRatio.heightToWidth
    }
  #endif

  private var bottomPadding: CGFloat {
    LayoutConfig.dashboardSectionBottomPadding(gradientBackground: showGradientBackground)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        NavigationLink(value: destination) {
          HStack {
            Text(section.displayName)
              .font(.title2)
              .bold()
              .fontDesign(.serif)
            Image(systemName: "chevron.right")
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Spacer()

        if showsCardKindMenu {
          DashboardCardKindMenu(section: section)
        }
      }
      .padding(.horizontal)
      .padding(.top, LayoutConfig.dashboardSectionTopPadding)
      #if os(macOS)
        .padding(.leading, 16)
      #endif

      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          content()
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
            itemIds: itemIds,
            contentFrame: stripContentFrame,
            horizontalContentMargin: LayoutConfig.defaultSpacing,
            coverHeight: scrollArrowsCoverHeight
          )
          // macOS keeps the vertical padding outside the scroll view so the
          // arrows overlay hugs the card strip; elsewhere it stays in the
          // content so the padding area still drags the strip.
          .padding(.top, LayoutConfig.dashboardSectionHeaderSpacing)
          .padding(.bottom, bottomPadding)
        #endif
      }
    }
    // The gradient rides in .background so its ignoresSafeArea sizing can never
    // inflate the band: as a ZStack sibling it made the band wider than the
    // screen whenever safe-area insets churned (rotation), looping the layout.
    .background {
      #if os(iOS) || os(macOS)
        if showGradientBackground {
          LinearGradient(
            colors: [Color.dashboardGradientStart, Color.dashboardGradientEnd],
            startPoint: .top,
            endPoint: .bottom
          ).ignoresSafeArea()
        }
      #endif
    }
  }
}
