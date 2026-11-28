#if os(iOS) || os(macOS)
  import CoreGraphics
  import Foundation

  enum WebPubInfoOverlaySupport {
    enum FlowStyle {
      case paged
      case scrolled
    }

    #if os(macOS)
      struct Entry: Equatable {
        let text: String?
        let isVisible: Bool

        static let hidden = Entry(text: nil, isVisible: false)
      }

      struct Content: Equatable {
        let showingControls: Bool
        let topLeading: Entry
        let topCenter: Entry
        let topTrailing: Entry
        let bottomLeading: Entry
        let bottomCenter: Entry
        let bottomTrailing: Entry
        let bottomProgress: Double?
        let isRTL: Bool
      }

      static func containerInsets(topOffset: CGFloat, bottomOffset: CGFloat) -> ReaderContainerInsets {
        ReaderContainerInsets(top: topOffset + 24, left: 0, bottom: bottomOffset + 24, right: 0)
      }

      static func content(
        flowStyle: FlowStyle,
        bookTitle: String?,
        chapterTitle: String?,
        totalProgression: Double?,
        currentPageIndex: Int,
        totalPagesInChapter: Int,
        showingControls: Bool,
        isRTL: Bool,
        overlayPreferences: EpubOverlayPreferences = AppConfig.epubOverlayPreferences
      ) -> Content {
        if showingControls {
          let controlsHeader = entry(
            for: .chapterRemaining,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          )
          let controlsFooter = entry(
            for: .chapterPosition,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          )
          return Content(
            showingControls: showingControls,
            topLeading: .hidden,
            topCenter: controlsHeader,
            topTrailing: .hidden,
            bottomLeading: .hidden,
            bottomCenter: controlsFooter,
            bottomTrailing: .hidden,
            bottomProgress: nil,
            isRTL: isRTL
          )
        }

        return Content(
          showingControls: showingControls,
          topLeading: entry(
            for: overlayPreferences.readerHeaderLeading,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
          topCenter: entry(
            for: overlayPreferences.readerHeaderCenter,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
          topTrailing: entry(
            for: overlayPreferences.readerHeaderTrailing,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
          bottomLeading: entry(
            for: overlayPreferences.readerFooterLeading,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
          bottomCenter: entry(
            for: overlayPreferences.readerFooterCenter,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
          bottomTrailing: entry(
            for: overlayPreferences.readerFooterTrailing,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
          bottomProgress: overlayPreferences.showsReaderProgressBar ? totalProgression.map(clampedProgress) : nil,
          isRTL: isRTL
        )
      }

      private static func visibleEntry(_ text: String?) -> Entry {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
          return .hidden
        }
        return Entry(text: trimmed, isVisible: true)
      }

      private static func entry(
        for item: EpubOverlayTextItem,
        flowStyle: FlowStyle,
        bookTitle: String?,
        chapterTitle: String?,
        totalProgression: Double?,
        currentPageIndex: Int,
        totalPagesInChapter: Int
      ) -> Entry {
        visibleEntry(
          text(
            for: item,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          )
        )
      }
    #endif

    static func text(
      for item: EpubOverlayTextItem,
      flowStyle: FlowStyle = .paged,
      bookTitle: String? = nil,
      chapterTitle: String? = nil,
      totalProgression: Double? = nil,
      currentPageIndex: Int = 0,
      totalPagesInChapter: Int = 0,
      bookPage: Int? = nil,
      totalBookPages: Int? = nil
    ) -> String? {
      switch item {
      case .none:
        return nil
      case .bookTitle:
        return bookTitle
      case .chapterTitle:
        return chapterTitle
      case .bookProgressPercent:
        guard let totalProgression else { return nil }
        let percentage = clampedProgress(totalProgression).formatted(.percent.precision(.fractionLength(2)))
        return String(localized: "Book Progress \(percentage)")
      case .bookRemainingPercent:
        guard let totalProgression else { return nil }
        let remaining = (1.0 - clampedProgress(totalProgression)).formatted(.percent.precision(.fractionLength(2)))
        return String(localized: "\(remaining) left")
      case .chapterProgressPercent:
        guard totalPagesInChapter > 0 else { return nil }
        let progress = chapterProgress(
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
        let percentage = progress.formatted(.percent.precision(.fractionLength(1)))
        return String(localized: "Chapter Progress \(percentage)")
      case .chapterRemaining:
        guard totalPagesInChapter > 0 else { return nil }
        return chapterRemainingText(
          flowStyle: flowStyle,
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
      case .chapterPosition:
        guard totalPagesInChapter > 0 else { return nil }
        return chapterPositionText(
          flowStyle: flowStyle,
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
      case .bookPosition:
        guard let bookPage, let totalBookPages, bookPage > 0, totalBookPages > 0 else { return nil }
        return String(localized: "\(bookPage) of \(totalBookPages)")
      }
    }

    private static func chapterPositionText(
      flowStyle: FlowStyle,
      currentPageIndex: Int,
      totalPagesInChapter: Int
    ) -> String {
      switch flowStyle {
      case .paged:
        let current = currentPageIndex + 1
        return String(localized: "Chapter Progress \(current) / \(totalPagesInChapter)")
      case .scrolled:
        let progress = chapterProgress(
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
        let percentage = progress.formatted(.percent.precision(.fractionLength(1)))
        return String(localized: "Chapter Progress \(percentage)")
      }
    }

    private static func chapterRemainingText(
      flowStyle: FlowStyle,
      currentPageIndex: Int,
      totalPagesInChapter: Int
    ) -> String {
      switch flowStyle {
      case .paged:
        let remainingPages = totalPagesInChapter - (currentPageIndex + 1)
        return
          remainingPages > 0
          ? String(localized: "\(remainingPages) pages left")
          : String(localized: "Last page")
      case .scrolled:
        let progress = chapterProgress(
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
        let remaining = (1.0 - progress).formatted(.percent.precision(.fractionLength(1)))
        return String(localized: "\(remaining) left")
      }
    }

    private static func chapterProgress(
      currentPageIndex: Int,
      totalPagesInChapter: Int
    ) -> Double {
      clampedProgress(Double(currentPageIndex + 1) / Double(totalPagesInChapter))
    }

    private static func clampedProgress(_ value: Double) -> Double {
      min(1.0, max(0.0, value))
    }
  }
#endif
