//
// PageFilmstripView.swift
//
//

import SwiftUI

/// Filmstrip for paged DIVINA modes: page thumbnails centered
/// on the current page. The strip is not independently scrollable — it follows
/// the committed page, taps jump, and dragging scrubs pages in real time.
struct PageFilmstripView: View {
  let pages: [ReaderPage]
  let currentPageID: ReaderPageID?
  let readingDirection: ReadingDirection
  let displayPageNumber: (ReaderPageID) -> Int
  let onSelect: (ReaderPageID) -> Void

  @State private var isDragging = false
  @State private var dragOffset: CGFloat = 0
  @State private var scrubStartIndex: Int?
  @State private var lastScrubbedIndex: Int?

  private static let itemWidth: CGFloat = 20
  private static let itemHeight: CGFloat = 30
  private static let currentItemWidth: CGFloat = 75
  private static let spacing: CGFloat = 2
  private static let currentSpacing: CGFloat = 8

  private static var itemAdvance: CGFloat {
    itemWidth + spacing
  }

  private var currentIndex: Int? {
    guard let currentPageID else { return nil }
    return pages.firstIndex(where: { $0.id == currentPageID })
  }

  private func itemWidth(for pageID: ReaderPageID) -> CGFloat {
    pageID == currentPageID ? Self.currentItemWidth : Self.itemWidth
  }

  private func itemHorizontalPadding(for pageID: ReaderPageID) -> CGFloat {
    pageID == currentPageID ? (Self.currentSpacing - Self.spacing) / 2 : 0
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: Self.spacing) {
          ForEach(pages) { page in
            PageFilmstripItemView(
              bookId: page.bookId,
              pageNumber: page.pageNumber,
              isCurrent: page.id == currentPageID,
              width: itemWidth(for: page.id),
              height: Self.itemHeight,
              horizontalPadding: itemHorizontalPadding(for: page.id),
              onTap: { onSelect(page.id) }
            )
            .accessibilityLabel(
              Text(
                String.localizedStringWithFormat(
                  String(localized: "Page %d"),
                  displayPageNumber(page.id)
                )
              )
            )
            .id(page.id)
          }
        }
        .offset(x: dragOffset)
        .animation(.appCurve(0.25), value: currentPageID)
      }
      .scrollDisabled(true)
      .environment(
        \.layoutDirection,
        readingDirection == .rtl ? .rightToLeft : .leftToRight
      )
      #if !os(tvOS)
        .gesture(scrubGesture)
      #endif
      .onAppear {
        proxy.scrollTo(currentPageID, anchor: .center)
      }
      .onChange(of: currentPageID) { _, newValue in
        guard let newValue else { return }
        if isDragging {
          proxy.scrollTo(newValue, anchor: .center)
        } else {
          withAnimation(.appSpring) {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
    }
    .frame(height: Self.itemHeight)
  }

  #if !os(tvOS)
    private var scrubGesture: some Gesture {
      DragGesture(minimumDistance: 10, coordinateSpace: .local)
        .onChanged { value in
          if !isDragging {
            isDragging = true
            HapticFeedback.prepare()
          }
          if scrubStartIndex == nil {
            scrubStartIndex = currentIndex
          }
          guard let startIndex = scrubStartIndex, !pages.isEmpty else { return }
          let directionSign: CGFloat = readingDirection == .rtl ? 1 : -1
          let rawTranslation = value.translation.width
          let delta = Int((rawTranslation * directionSign / Self.itemAdvance).rounded())
          let target = min(max(startIndex + delta, 0), pages.count - 1)
          dragOffset = rawTranslation - CGFloat(delta) * Self.itemAdvance * directionSign
          guard target != lastScrubbedIndex, target != currentIndex else { return }
          lastScrubbedIndex = target
          HapticFeedback.selectionChanged()
          onSelect(pages[target].id)
        }
        .onEnded { _ in
          isDragging = false
          scrubStartIndex = nil
          lastScrubbedIndex = nil
          withAnimation(.appSpring) {
            dragOffset = 0
          }
        }
    }
  #endif
}
