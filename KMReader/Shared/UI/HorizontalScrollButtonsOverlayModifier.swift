//
// HorizontalScrollButtonsOverlayModifier.swift
//
//

import SwiftUI

#if os(macOS)
  private struct HorizontalScrollButtonsOverlayModifier<ID: Hashable>: ViewModifier {
    let scrollProxy: ScrollViewProxy
    let itemIds: [ID]
    let contentFrame: CGRect
    let horizontalContentMargin: CGFloat

    @State private var areButtonsVisible = false

    func body(content: Content) -> some View {
      content
        .overlay {
          HorizontalScrollButtons(
            scrollProxy: scrollProxy,
            itemIds: itemIds,
            isVisible: areButtonsVisible,
            contentFrame: contentFrame,
            horizontalContentMargin: horizontalContentMargin
          )
        }
        .onHover { hovering in
          guard areButtonsVisible != hovering else { return }
          areButtonsVisible = hovering
        }
    }
  }

  extension View {
    func macHorizontalScrollButtons<ID: Hashable>(
      scrollProxy: ScrollViewProxy,
      itemIds: [ID],
      contentFrame: CGRect,
      horizontalContentMargin: CGFloat
    ) -> some View {
      modifier(
        HorizontalScrollButtonsOverlayModifier(
          scrollProxy: scrollProxy,
          itemIds: itemIds,
          contentFrame: contentFrame,
          horizontalContentMargin: horizontalContentMargin
        )
      )
    }
  }
#endif
