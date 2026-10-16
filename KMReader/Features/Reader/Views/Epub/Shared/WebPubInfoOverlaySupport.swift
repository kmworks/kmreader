#if os(iOS) || os(macOS)
  import CoreGraphics
  import Foundation

  enum WebPubInfoOverlaySupport {
    enum FlowStyle {
      case paged
      case scrolled
    }

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
        return Content(
          showingControls: showingControls,
          topLeading: .hidden,
          topCenter: entry(
            for: overlayPreferences.controlsHeaderCenter,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
          topTrailing: .hidden,
          bottomLeading: .hidden,
          bottomCenter: entry(
            for: overlayPreferences.controlsFooterCenter,
            flowStyle: flowStyle,
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            totalProgression: totalProgression,
            currentPageIndex: currentPageIndex,
            totalPagesInChapter: totalPagesInChapter
          ),
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
      switch item {
      case .none:
        return .hidden
      case .bookTitle:
        return visibleEntry(bookTitle)
      case .chapterTitle:
        return visibleEntry(chapterTitle)
      case .bookProgressPercent:
        guard let totalProgression else { return .hidden }
        let percentage = clampedProgress(totalProgression).formatted(.percent.precision(.fractionLength(2)))
        return Entry(
          text: String(localized: "Book Progress \(percentage)"),
          isVisible: true
        )
      case .bookRemainingPercent:
        guard let totalProgression else { return .hidden }
        let remaining = (1.0 - clampedProgress(totalProgression)).formatted(.percent.precision(.fractionLength(2)))
        return Entry(text: String(localized: "\(remaining) left"), isVisible: true)
      case .chapterProgressPercent:
        guard totalPagesInChapter > 0 else { return .hidden }
        let progress = chapterProgress(
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
        let percentage = progress.formatted(.percent.precision(.fractionLength(1)))
        return Entry(
          text: String(localized: "Chapter Progress \(percentage)"),
          isVisible: true
        )
      case .chapterRemaining:
        guard totalPagesInChapter > 0 else { return .hidden }
        return chapterRemainingEntry(
          flowStyle: flowStyle,
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
      case .chapterPosition:
        guard totalPagesInChapter > 0 else { return .hidden }
        return chapterPositionEntry(
          flowStyle: flowStyle,
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
      }
    }

    private static func chapterPositionEntry(
      flowStyle: FlowStyle,
      currentPageIndex: Int,
      totalPagesInChapter: Int
    ) -> Entry {
      switch flowStyle {
      case .paged:
        let current = currentPageIndex + 1
        return Entry(
          text: String(localized: "Chapter Progress \(current) / \(totalPagesInChapter)"),
          isVisible: true
        )
      case .scrolled:
        let progress = chapterProgress(
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
        let percentage = progress.formatted(.percent.precision(.fractionLength(1)))
        return Entry(
          text: String(localized: "Chapter Progress \(percentage)"),
          isVisible: true
        )
      }
    }

    private static func chapterRemainingEntry(
      flowStyle: FlowStyle,
      currentPageIndex: Int,
      totalPagesInChapter: Int
    ) -> Entry {
      switch flowStyle {
      case .paged:
        let remainingPages = totalPagesInChapter - (currentPageIndex + 1)
        let text =
          remainingPages > 0
          ? String(localized: "\(remainingPages) pages left")
          : String(localized: "Last page")
        return Entry(text: text, isVisible: true)
      case .scrolled:
        let progress = chapterProgress(
          currentPageIndex: currentPageIndex,
          totalPagesInChapter: totalPagesInChapter
        )
        let remaining = (1.0 - progress).formatted(.percent.precision(.fractionLength(1)))
        return Entry(text: String(localized: "\(remaining) left"), isVisible: true)
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
