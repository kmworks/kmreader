//
// HorizontalScrollButtons.swift
//
//

import SwiftUI

#if os(macOS)
  /// Overlay buttons for horizontal ScrollView navigation (left/right arrows)
  /// Only visible on macOS, visibility controlled by parent via isVisible
  struct HorizontalScrollButtons<ID: Hashable>: View {
    let scrollProxy: ScrollViewProxy
    let itemIds: [ID]
    let isVisible: Bool
    /// Scroll-content frame in global coordinates; `.zero` until measured.
    let contentFrame: CGRect
    /// The scroll view's horizontal content margin. The buttons can only tell
    /// the rest and end positions from the content frame when the margin is
    /// known, since the frame never crosses into it.
    let horizontalContentMargin: CGFloat

    private var isMeasured: Bool {
      contentFrame.width > 0
    }

    private var itemStride: CGFloat {
      contentFrame.width / CGFloat(max(itemIds.count, 1))
    }

    var body: some View {
      GeometryReader { geometry in
        let viewportFrame = geometry.frame(in: .global)
        ZStack {
          if isVisible {
            scrollButton(direction: .left, viewportFrame: viewportFrame)
              .transition(.opacity)
              .frame(maxWidth: .infinity, alignment: .leading)

            scrollButton(direction: .right, viewportFrame: viewportFrame)
              .transition(.opacity)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
        }
      }
      .animation(.appCurve(0.15), value: isVisible)
      .allowsHitTesting(isVisible)
    }

    private enum ScrollDirection {
      case left
      case right

      var systemImage: String {
        switch self {
        case .left: "chevron.left"
        case .right: "chevron.right"
        }
      }
    }

    private func canScrollLeft(viewportFrame: CGRect) -> Bool {
      isMeasured && contentFrame.minX < viewportFrame.minX + horizontalContentMargin - 2
    }

    private func canScrollRight(viewportFrame: CGRect) -> Bool {
      guard isMeasured else { return itemIds.count > 1 }
      return contentFrame.maxX > viewportFrame.maxX - horizontalContentMargin + 2
    }

    private func offsetX(viewportFrame: CGRect) -> CGFloat {
      max(0, viewportFrame.minX + horizontalContentMargin - contentFrame.minX)
    }

    private func currentIndex(viewportFrame: CGRect) -> Int {
      guard isMeasured, itemStride > 0 else { return 0 }
      return min(itemIds.count - 1, max(0, Int((offsetX(viewportFrame: viewportFrame) / itemStride).rounded())))
    }

    private func step(viewportFrame: CGRect) -> Int {
      guard isMeasured, itemStride > 0 else { return 5 }
      return max(1, Int(viewportFrame.width / itemStride))
    }

    @ViewBuilder
    private func scrollButton(direction: ScrollDirection, viewportFrame: CGRect) -> some View {
      let canScroll =
        direction == .left
        ? canScrollLeft(viewportFrame: viewportFrame)
        : canScrollRight(viewportFrame: viewportFrame)

      Button {
        let index = currentIndex(viewportFrame: viewportFrame)
        let distance = step(viewportFrame: viewportFrame)
        let target =
          direction == .left
          ? max(0, index - distance)
          : min(itemIds.count - 1, index + distance)
        if let itemId = itemIds[safe: target] {
          withAnimation(.appCurve(0.3)) {
            scrollProxy.scrollTo(itemId, anchor: .center)
          }
        }
      } label: {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.thinMaterial)
            .frame(width: 24, height: 60)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)

          Image(systemName: direction.systemImage)
            .foregroundStyle(canScroll ? .primary : .secondary)
            .bold()
            .scaleEffect(x: 1.0, y: 2.5)
        }
        .padding(8)
        .contentShape(Rectangle())
      }
      .adaptiveButtonStyle(.plain)
      .opacity(canScroll ? 1 : 0.6)
      .disabled(!canScroll)
    }
  }

  extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
      indices.contains(index) ? self[index] : nil
    }
  }
#endif
