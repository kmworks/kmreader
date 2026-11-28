//
// EpubProgressScrubberView.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Apple Books–style bottom progress bar: a quiet track at rest that expands
  /// and thickens on long-press into a full-width scrubber with chapter ticks
  /// and a floating callout naming the destination chapter and page.
  struct EpubProgressScrubberView: View {
    let viewModel: EpubReaderViewModel
    let theme: ReaderTheme
    let restingHorizontalInset: CGFloat
    @Binding var isScrubbing: Bool

    @State private var scrubFraction: Double?
    @State private var pendingSeekFraction: Double?
    @State private var lastHapticPage: Int?

    private static let restingMaxTrackWidth: CGFloat = 360
    private static let minimumTrackWidth: CGFloat = 80
    private static let trackHeight: CGFloat = 5
    private static let activeTrackHeight: CGFloat = 12
    // Layout reserves only the resting height; the active track overflows
    // symmetrically around centerY so scrubbing never changes bar height.
    private static let trackLayoutHeight: CGFloat = 5
    private static let trackHitHeight: CGFloat = 32
    private static let minimumTickSpacing: CGFloat = 12

    private var baselineFraction: Double {
      viewModel.totalSeekFraction ?? 0
    }

    private var displayedFraction: Double {
      if let scrubFraction { return scrubFraction }
      // Hold the release target while a jump is in flight so the fill does not
      // snap back to the old page mid-collapse.
      if viewModel.navigationRequest != nil, let pendingSeekFraction { return pendingSeekFraction }
      return baselineFraction
    }

    private var isRTL: Bool {
      viewModel.publicationReadingProgression == .rtl
    }

    private var footerText: String? {
      WebPubInfoOverlaySupport.text(
        for: .bookPosition,
        flowStyle: .paged,
        bookTitle: nil,
        chapterTitle: nil,
        totalProgression: nil,
        currentPageIndex: 0,
        totalPagesInChapter: 0,
        bookPage: viewModel.bookPageProgress?.currentPage,
        totalBookPages: viewModel.bookPageProgress?.totalPages
      )
    }

    var body: some View {
      VStack(spacing: 8) {
        GeometryReader { proxy in
          trackContainer(in: proxy.size)
        }
        .frame(height: Self.trackLayoutHeight)

        if let footerText {
          Text(footerText)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(theme.textColor.opacity(0.62))
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.appCurve(0.2), value: footerText)
            .allowsHitTesting(false)
        }
      }
    }

    private func trackWidth(for containerWidth: CGFloat, scrubbing: Bool) -> CGFloat {
      if scrubbing { return containerWidth }
      let inset = min(restingHorizontalInset, max(0, (containerWidth - Self.minimumTrackWidth) / 2))
      return max(
        Self.minimumTrackWidth,
        min(containerWidth - inset * 2, Self.restingMaxTrackWidth)
      )
    }

    private func trackContainer(in size: CGSize) -> some View {
      let scrubbing = isScrubbing
      let restingWidth = trackWidth(for: size.width, scrubbing: false)
      let width = trackWidth(for: size.width, scrubbing: scrubbing)
      let height = scrubbing ? Self.activeTrackHeight : Self.trackHeight
      let originX = (size.width - width) / 2
      let centerY = size.height / 2

      return ZStack(alignment: .topLeading) {
        trackVisual(width: width, height: height, scrubbing: scrubbing)
          .scaleEffect(x: isRTL ? -1 : 1, y: 1)
          .frame(width: width, height: height)
          .position(x: originX + width / 2, y: centerY)
          .allowsHitTesting(false)

        EpubScrubGestureView(
          restingTrackWidth: restingWidth,
          isScrubbing: isScrubbing,
          interfaceStyle: theme.isDark ? .dark : .light,
          previewAtPoint: { x in preview(atX: x, containerWidth: size.width) },
          onBegan: beginScrub,
          onChanged: updateScrub,
          onEnded: endScrub,
          onCancelled: cancelScrub
        )
        .frame(width: size.width, height: Self.trackHitHeight)
        .position(x: size.width / 2, y: centerY)
      }
      .frame(width: size.width, height: size.height)
      .overlay {
        Color.clear
          .frame(width: restingWidth, height: Self.trackHitHeight)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text("Reading Progress"))
          .accessibilityValue(Text(baselineFraction.formatted(.percent.precision(.fractionLength(0)))))
          .accessibilityAdjustableAction { direction in
            adjustAccessibly(direction)
          }
      }
    }

    private func trackVisual(width: CGFloat, height: CGFloat, scrubbing: Bool) -> some View {
      let progress = min(max(displayedFraction, 0), 1)
      let fillWidth = max(width * progress, progress > 0 ? height : 0)

      return ZStack(alignment: .leading) {
        Capsule()
          .fill(theme.textColor.opacity(scrubbing ? 0.26 : 0.24))

        Capsule()
          .fill(theme.textColor.opacity(0.78))
          .frame(width: fillWidth)

        // Always mounted: fades with expansion and paints background-colored
        // gaps directly, avoiding an offscreen destinationOut compositing pass.
        chapterTicks(width: width, height: height)
          .opacity(scrubbing ? 1 : 0)

        if let returnFraction = viewModel.returnSeekFraction {
          let clampedReturn = min(max(returnFraction, 0), 1)
          let isInsideFill = clampedReturn <= progress
          Capsule()
            .fill(isInsideFill ? theme.backgroundColor.opacity(0.9) : theme.textColor.opacity(0.75))
            .frame(width: 2.5, height: height)
            .position(x: min(max(clampedReturn * width, 2), width - 2), y: height / 2)
        }
      }
      .frame(width: width, height: height)
      .clipShape(Capsule())
    }

    private func chapterTicks(width: CGFloat, height: CGFloat) -> some View {
      var lastX: CGFloat = -.infinity
      let boundaries = viewModel.chapterBoundaryFractions.filter { fraction in
        let x = min(max(fraction, 0), 1) * width
        guard x >= Self.minimumTickSpacing, x <= width - Self.minimumTickSpacing,
          x - lastX >= Self.minimumTickSpacing
        else { return false }
        lastX = x
        return true
      }

      return Canvas { context, _ in
        for fraction in boundaries {
          let x = min(max(fraction, 0), 1) * width
          let rect = CGRect(x: x - 1, y: 0, width: 2, height: height)
          context.fill(Path(rect), with: .color(theme.backgroundColor))
        }
      }
      .frame(width: width, height: height)
    }

    private func preview(atX x: CGFloat, containerWidth: CGFloat) -> EpubScrubPreview? {
      guard containerWidth > 0 else { return nil }
      let raw = min(max(x / containerWidth, 0), 1)
      let fraction = isRTL ? 1 - raw : raw
      return viewModel.scrubPreview(forTotalFraction: fraction)
    }

    private func beginScrub(_ preview: EpubScrubPreview) {
      guard !isScrubbing else { return }
      HapticFeedback.light()
      // Batch expansion and initial grab fraction in one transaction so the
      // outer frame, position, height, and fill animate together.
      withAnimation(.appCurve(0.24)) {
        lastHapticPage = preview.bookPage
        scrubFraction = preview.fraction
        isScrubbing = true
      }
    }

    private func updateScrub(_ preview: EpubScrubPreview) {
      guard isScrubbing else { return }
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        scrubFraction = preview.fraction
      }
      if let last = lastHapticPage, last != preview.bookPage {
        HapticFeedback.selectionChanged()
      }
      lastHapticPage = preview.bookPage
    }

    private func endScrub(_ preview: EpubScrubPreview?) {
      guard isScrubbing else { return }
      HapticFeedback.light()
      let didSeek = preview.map { viewModel.seek(toTotalFraction: $0.fraction) } ?? false
      withAnimation(.appCurve(0.24)) {
        pendingSeekFraction = didSeek ? preview?.fraction : nil
        scrubFraction = nil
        lastHapticPage = nil
        isScrubbing = false
      }
    }

    private func cancelScrub() {
      guard isScrubbing else { return }
      HapticFeedback.light()
      withAnimation(.appCurve(0.24)) {
        pendingSeekFraction = nil
        scrubFraction = nil
        lastHapticPage = nil
        isScrubbing = false
      }
    }

    private func adjustAccessibly(_ direction: AccessibilityAdjustmentDirection) {
      switch direction {
      case .increment:
        HapticFeedback.selectionChanged()
        viewModel.stepSeekPosition(pageOffset: 1)
      case .decrement:
        HapticFeedback.selectionChanged()
        viewModel.stepSeekPosition(pageOffset: -1)
      @unknown default:
        break
      }
    }
  }
#endif
