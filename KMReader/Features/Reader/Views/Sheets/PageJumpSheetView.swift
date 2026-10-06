//
// PageJumpSheetView.swift
//
//

import SwiftUI

// Loads the page thumbnail, then renders the shared preview card.
private struct LoadedPagePreviewCard: View {

  let readerPage: ReaderPage
  let displayPage: Int
  let isSelected: Bool
  let imageHeight: CGFloat

  @State private var loadedImage: PlatformImage?

  var body: some View {
    PageJumpPreviewCard(
      displayPage: displayPage,
      image: loadedImage,
      isSelected: isSelected,
      imageHeight: imageHeight
    )
    .task(id: "\(readerPage.id.description)-\(Int(imageHeight))") {
      loadedImage = nil
      loadedImage = await ThumbnailCache.shared.image(
        id: readerPage.bookId,
        type: .page,
        page: readerPage.pageNumber
      )
    }
  }
}

struct PageJumpSheetView: View {
  let segmentBookId: String
  let currentPageID: ReaderPageID?
  let readingDirection: ReadingDirection
  let viewModel: ReaderViewModel
  let onJump: (ReaderPageID) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var pageValue: Int
  @State private var scrollPosition: Int?

  private var currentSegmentPages: [ReaderPage] {
    viewModel.segmentReaderPages(forSegmentBookId: segmentBookId)
  }

  private var totalPages: Int {
    pagePreviews.count
  }

  private var pagePreviews: [PagePreview] {
    currentSegmentPages.enumerated().map { localIndex, readerPage in
      return PagePreview(
        id: localIndex + 1,
        pageID: readerPage.id,
        readerPage: readerPage
      )
    }
  }

  private var maxPage: Int {
    max(totalPages, 1)
  }

  private var canJump: Bool {
    totalPages > 0
  }

  private var currentPageNumber: Int {
    guard canJump else { return 0 }
    if let currentPageID,
      let currentIndex = currentSegmentPages.firstIndex(where: { $0.id == currentPageID })
    {
      return currentIndex + 1
    }
    return min(max(pageValue, 1), totalPages)
  }

  private var sliderBinding: Binding<Double> {
    Binding(
      get: { Double(pageValue) },
      set: { newValue in
        let newPage = Int(newValue.rounded())
        if newPage != pageValue {
          pageValue = newPage
        }
      }
    )
  }

  init(
    segmentBookId: String,
    currentPageID: ReaderPageID?,
    readingDirection: ReadingDirection = .ltr,
    viewModel: ReaderViewModel,
    onJump: @escaping (ReaderPageID) -> Void
  ) {
    self.segmentBookId = segmentBookId
    self.currentPageID = currentPageID
    self.readingDirection = readingDirection
    self.viewModel = viewModel
    self.onJump = onJump

    let segmentPages = viewModel.segmentReaderPages(forSegmentBookId: segmentBookId)
    let initialPage =
      currentPageID.flatMap { pageID in
        segmentPages.firstIndex(where: { $0.id == pageID }).map { $0 + 1 }
      } ?? 1
    let safeInitialPage = max(1, min(initialPage, max(segmentPages.count, 1)))
    _pageValue = State(initialValue: safeInitialPage)
    _scrollPosition = State(initialValue: safeInitialPage)
  }

  private var sliderScaleX: CGFloat {
    readingDirection == .rtl ? -1 : 1
  }

  private var pageLabels: (left: String, right: String) {
    if readingDirection == .rtl {
      return (left: "\(totalPages)", right: "1")
    } else {
      return (left: "1", right: "\(totalPages)")
    }
  }

  private func pagePreview(localPage: Int) -> PagePreview? {
    pagePreviews.first(where: { $0.id == localPage })
  }

  private func jumpToPage() {
    guard canJump else { return }
    let clampedValue = min(max(pageValue, 1), totalPages)
    guard let preview = pagePreview(localPage: clampedValue) else { return }
    onJump(preview.pageID)
    dismiss()
  }

  private func adjustPage(step: Int) {
    guard canJump else { return }
    let newValue = min(max(pageValue + step, 1), maxPage)
    pageValue = newValue
    scrollPosition = newValue
  }

  #if os(iOS) || os(macOS)
    private func sharePage() async {
      let pageNumber = pageValue
      guard pageNumber > 0 && pageNumber <= totalPages else { return }
      guard let preview = pagePreview(localPage: pageNumber) else { return }
      let readerPage = preview.readerPage

      // Use viewModel's method to get page image (checks cache, offline, downloads if needed)
      guard let fileURL = await viewModel.getPageImageFileURL(pageID: preview.pageID) else { return }
      guard let image = PlatformImage(contentsOfFile: fileURL.path) else { return }

      ImageShareHelper.shareMultiple(images: [image], fileNames: [readerPage.page.fileName])
    }
  #endif

  var body: some View {
    SheetView(title: String(localized: "Go to Page"), size: .medium) {
      VStack(spacing: 16) {
        if canJump {
          Text("Current page: \(currentPageNumber)")
            .foregroundStyle(.secondary)
        }

        if canJump {
          VStack(spacing: 16) {
            // Native paging scroll view
            GeometryReader { geometry in
              let imageHeight = min(geometry.size.height - 40, 250)

              ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                  LazyHStack(spacing: 8) {
                    ForEach(pagePreviews) { preview in
                      LoadedPagePreviewCard(
                        readerPage: preview.readerPage,
                        displayPage: preview.id,
                        isSelected: preview.id == pageValue,
                        imageHeight: imageHeight
                      )
                      .id(preview.id)
                      .onTapGesture {
                        pageValue = preview.id
                        scrollPosition = preview.id
                      }
                    }
                  }
                  .scrollTargetLayout()
                }
                .contentMargins(
                  .horizontal,
                  (geometry.size.width - imageHeight * PageJumpPreviewCard.widthRatio) / 2,
                  for: .scrollContent
                )
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollPosition, anchor: .center)
                .environment(
                  \.layoutDirection, readingDirection == .rtl ? .rightToLeft : .leftToRight
                )
                .onAppear {
                  // Initial scroll to current page
                  proxy.scrollTo(pageValue, anchor: .center)
                }
                .onChange(of: scrollPosition) { _, newValue in
                  // User scrolled - update pageValue
                  if let page = newValue {
                    pageValue = page
                  }
                }
                .onChange(of: pageValue) { oldValue, newValue in
                  // Slider changed - scroll to new page (only if different from scroll position)
                  if scrollPosition != newValue {
                    withAnimation(.appSpring) {
                      proxy.scrollTo(newValue, anchor: .center)
                    }
                  }
                }
              }
            }
            .frame(minHeight: 200, maxHeight: 320)

            #if os(tvOS)
              VStack(spacing: 40) {
                HStack(spacing: 20) {
                  Text(pageLabels.left)
                    .foregroundStyle(.secondary)
                  Button {
                    adjustPage(step: readingDirection == .rtl ? 1 : -1)
                  } label: {
                    Image(
                      systemName: readingDirection == .rtl
                        ? "plus.circle.fill" : "minus.circle.fill")
                  }

                  Text("Page \(pageValue)")
                    .monospacedDigit()

                  Button {
                    adjustPage(step: readingDirection == .rtl ? -1 : 1)
                  } label: {
                    Image(
                      systemName: readingDirection == .rtl
                        ? "minus.circle.fill" : "plus.circle.fill")
                  }
                  Text(pageLabels.right)
                    .foregroundStyle(.secondary)
                }

                Button {
                  jumpToPage()
                } label: {
                  HStack(spacing: 4) {
                    Spacer()
                    Text("Jump")
                    Image(systemName: AppIcon.pageJump)
                    Spacer()
                  }
                }
                .adaptiveButtonStyle(.borderedProminent)
                .disabled(!canJump || pageValue == currentPageNumber)
              }
              .focusSection()
            #else
              VStack(spacing: 0) {
                Slider(
                  value: sliderBinding,
                  in: 1...Double(maxPage),
                  step: 1
                )
                .scaleEffect(x: sliderScaleX, y: 1)
                HStack {
                  Text(pageLabels.left)
                  Spacer()
                  Text(pageLabels.right)
                }
                .foregroundStyle(.secondary)
              }

              HStack {
                Button {
                  jumpToPage()
                } label: {
                  HStack(spacing: 4) {
                    Text("Jump")
                    Image(systemName: AppIcon.pageJump)
                  }
                }
                .adaptiveButtonStyle(.borderedProminent)
                .disabled(!canJump || pageValue == currentPageNumber)
              }
            #endif
          }
        }
        Spacer()
      }
      .padding()
    } controls: {
      #if os(iOS) || os(macOS)
        Button {
          Task {
            await sharePage()
          }
        } label: {
          Image(systemName: AppIcon.share)
        }
        .disabled(!canJump)
      #endif
    }
    .presentationDragIndicator(.visible)
  }
}

private struct PagePreview: Identifiable {
  let id: Int
  let pageID: ReaderPageID
  let readerPage: ReaderPage
}
