//
// DashboardSectionLayout.swift
//
//

import SwiftUI

/// Shared dashboard section chrome: gradient band, header navigation link,
/// and the horizontal card strip. Owns the band's vertical rhythm so every
/// section reads the same; empty sections collapse to zero height.
@MainActor
struct DashboardSectionLayout<Content: View>: View {
  let section: DashboardSection
  let destination: NavDestination
  let showsCardKindMenu: Bool
  let isEmpty: Bool
  let itemIds: [String]
  @ViewBuilder let content: () -> Content

  @AppStorage("showDashboardSectionGradientBackground")
  private var showGradientBackground: Bool =
    AppConfig.showDashboardSectionGradientBackground

  private var verticalPadding: CGFloat {
    showGradientBackground
      ? LayoutConfig.dashboardSectionVerticalPadding
      : LayoutConfig.dashboardSectionVerticalPaddingCompact
  }

  var body: some View {
    ZStack {
      #if os(iOS) || os(macOS)
        if showGradientBackground {
          LinearGradient(
            colors: [Color.dashboardGradientStart, Color.dashboardGradientEnd],
            startPoint: .top,
            endPoint: .bottom
          ).ignoresSafeArea()
        }
      #endif

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
          .disabled(isEmpty)

          Spacer()

          if showsCardKindMenu {
            DashboardCardKindMenu(section: section)
          }
        }
        .padding(.horizontal)
        .padding(.top, verticalPadding)
        #if os(macOS)
          .padding(.leading, 16)
        #endif

        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            content()
              .padding(.top, LayoutConfig.dashboardSectionHeaderSpacing)
              .padding(.bottom, verticalPadding)
              #if os(macOS)
                .padding(.leading, 16)
              #endif
          }
          .contentMargins(.horizontal, LayoutConfig.defaultSpacing, for: .scrollContent)
          .scrollClipDisabled()
          #if os(macOS)
            .macHorizontalScrollButtons(
              scrollProxy: proxy,
              itemIds: itemIds
            )
          #endif
        }
      }
    }
    .opacity(isEmpty ? 0 : 1)
    .frame(height: isEmpty ? 0 : nil)
  }
}
