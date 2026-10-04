//
// PageFilmstripView.swift
//
//

import SwiftUI

/// Filmstrip for paged DIVINA modes: page thumbnails centered
/// on the current page. The strip is not independently scrollable — it follows
/// the committed page, taps jump, and dragging scrubs pages in real time.
/// The current page's lens grows in both dimensions with its width derived
/// from the page's own aspect, so the full page stays visible instead of a
/// fill-cropped slice.
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
  /// The lens grows in both dimensions so a full page is always visible: width
  /// follows the page's own aspect, only ultra-wide pages get center-cropped.
  private static let lensHeight: CGFloat = 44
  private static let lensMaxWidth: CGFloat = 75
  private static let fallbackAspect: CGFloat = 2.0 / 3.0
  private static let spacing: CGFloat = 2
  private static let currentSpacing: CGFloat = 8

  private static var itemAdvance: CGFloat {
    itemWidth + spacing
  }

  private var currentIndex: Int? {
    guard let currentPageID else { return nil }
    return pages.firstIndex(where: { $0.id == currentPageID })
  }

  private func aspect(for page: ReaderPage) -> CGFloat {
    guard let width = page.page.width, let height = page.page.height, width > 0, height > 0
    else { return Self.fallbackAspect }
    return CGFloat(width) / CGFloat(height)
  }

  private func itemWidth(for page: ReaderPage) -> CGFloat {
    guard page.id == currentPageID else { return Self.itemWidth }
    return min(Self.lensMaxWidth, Self.lensHeight * aspect(for: page))
  }

  private func itemHeight(for page: ReaderPage) -> CGFloat {
    page.id == currentPageID ? Self.lensHeight : Self.itemHeight
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
              width: itemWidth(for: page),
              height: itemHeight(for: page),
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
        .animation(.appCurve(0.25), value: currentPageID)
        .offset(x: dragOffset)
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
          // Scrub re-centering must be instant — animating it makes the strip
          // glide behind the finger instead of tracking 1:1.
          withTransaction(Transaction(animation: nil)) {
            proxy.scrollTo(newValue, anchor: .center)
          }
        } else {
          withAnimation(.appSpring) {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
    }
    .frame(height: Self.lensHeight)
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
