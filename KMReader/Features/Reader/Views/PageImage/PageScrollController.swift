//
// PageScrollController.swift
//
//

#if os(iOS) || os(tvOS)
  import UIKit

  /// Owns a page host's zoom scroll view: pins the page content into it,
  /// passes zoom changes to the host, and shows a whole spread. For a whole
  /// spread it sizes the content, keeps the spread at its resting edge across
  /// item, viewport, and content-size changes, pans it for navigation, and
  /// reports where it rests while the host shows the committed page.
  @MainActor
  final class PageScrollController: NSObject, UIScrollViewDelegate {
    let scrollView: SpreadPanningScrollView
    weak var host: PageScrollControllerHost?
    private(set) var wholeSpread: WholeSpreadPresentation?

    private let contentView: UIView
    private let contentWidthConstraint: NSLayoutConstraint
    private weak var viewModel: ReaderViewModel?
    // Edge the whole spread keeps across layout changes: where it arrived,
    // then wherever its latest pan settled.
    private var restingEdge: ReaderSpreadEdge = .start
    private var needsPlacement = false
    private var lastViewportSize: CGSize = .zero

    init(contentView: UIView) {
      let scrollView = SpreadPanningScrollView()
      self.scrollView = scrollView
      self.contentView = contentView
      // A whole spread widens the content past the viewport by this
      // constraint's constant, so it pans at base zoom.
      contentWidthConstraint = contentView.widthAnchor.constraint(
        equalTo: scrollView.frameLayoutGuide.widthAnchor
      )
      super.init()

      scrollView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.delegate = self
      scrollView.minimumZoomScale = 1.0
      scrollView.maximumZoomScale = 8.0
      scrollView.showsHorizontalScrollIndicator = false
      scrollView.showsVerticalScrollIndicator = false
      scrollView.contentInsetAdjustmentBehavior = .never

      contentView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.addSubview(contentView)
      NSLayoutConstraint.activate([
        contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
        contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        contentWidthConstraint,
        contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
      ])
    }

    /// `wholeSpread` is set while the host shows its item as a whole spread.
    /// A new item opens at its arrival edge. A flipped start side, as from a
    /// reading direction change, keeps the edge in reading order and moves
    /// the spread to where that edge now is.
    func configure(
      viewModel: ReaderViewModel,
      wholeSpread: WholeSpreadPresentation?,
      itemChanged: Bool
    ) {
      let startSideChanged = wholeSpread?.startsAtLeft != self.wholeSpread?.startsAtLeft
      self.viewModel = viewModel
      self.wholeSpread = wholeSpread
      scrollView.spreadStartsAtLeft = wholeSpread?.startsAtLeft ?? true
      if itemChanged {
        restingEdge = wholeSpread?.arrivalEdge ?? .start
        needsPlacement = true
      } else if startSideChanged {
        needsPlacement = true
      }
    }

    /// Forgets the shown item, e.g. before the host is reused.
    func reset() {
      viewModel = nil
      wholeSpread = nil
      restingEdge = .start
      needsPlacement = true
    }

    /// Moves the whole spread back to its resting edge on the next layout,
    /// e.g. after the host resets its zoom.
    func setNeedsPlacement() {
      needsPlacement = true
    }

    /// Sizes the content for a whole spread, and places the spread at its
    /// resting edge when the item, viewport, or spread width changed.
    func updateLayout(viewportSize: CGSize) {
      guard viewportSize.width > 0, viewportSize.height > 0 else { return }
      if viewportSize != lastViewportSize {
        lastViewportSize = viewportSize
        needsPlacement = true
      }

      let contentWidth =
        spreadImageSize().map {
          WholeSpreadLayout.contentWidth(imageSize: $0, viewportSize: viewportSize)
        } ?? viewportSize.width
      let extraWidth = max(contentWidth - viewportSize.width, 0)
      if abs(contentWidthConstraint.constant - extraWidth) > 0.5 {
        contentWidthConstraint.constant = extraWidth
        needsPlacement = true
      }

      guard needsPlacement, scrollView.isAtBaseZoom else { return }
      needsPlacement = false
      scrollView.layoutIfNeeded()
      scrollView.placeSpread(at: restingEdge)
      reportPosition()
    }

    /// Pans the whole spread to `edge` for a navigation command.
    func panSpread(to edge: ReaderSpreadEdge, animated: Bool) {
      guard wholeSpread != nil, scrollView.isAtBaseZoom else { return }
      // A pan that cuts a glide short settles the spread where it is first,
      // so the edge is taken once the pan has started.
      scrollView.panSpread(to: edge, animated: animated)
      restingEdge = edge
      reportPosition()
    }

    /// Whether a horizontal drag would pan the whole spread rather than turn
    /// the page.
    func canPanSpread(forHorizontalDrag translationX: CGFloat) -> Bool {
      wholeSpread != nil && scrollView.canPanSpread(forHorizontalDrag: translationX)
    }

    /// Reports where the whole spread rests while the host shows the
    /// committed page.
    func reportPosition() {
      report(restingEdges: scrollView.restingSpreadEdges)
    }

    private func report(restingEdges: Set<ReaderSpreadEdge>) {
      guard let wholeSpread, let viewModel, host?.showsCommittedPage == true else { return }
      viewModel.recordWholeSpreadPosition(pageID: wholeSpread.pageID, restingEdges: restingEdges)
    }

    private func spreadImageSize() -> CGSize? {
      guard let wholeSpread, let viewModel else { return nil }
      if let size = host?.displayedImageSize(for: wholeSpread.pageID) {
        return size
      }
      guard let page = viewModel.readerPage(for: wholeSpread.pageID)?.page,
        let width = page.width, let height = page.height
      else {
        return nil
      }
      return viewModel.rotation.rotatedSize(CGSize(width: CGFloat(width), height: CGFloat(height)))
    }

    private func spreadPanDidSettle() {
      scrollView.clearPendingSpreadPan()
      guard wholeSpread != nil, scrollView.isAtBaseZoom else { return }
      restingEdge = scrollView.nearestSpreadEdge
      reportPosition()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      contentView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      host?.pageScrollControllerDidZoom(self)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
      self.scrollView.clearPendingSpreadPan()
      // Under a finger and while it glides, the spread rests at no edge, so a
      // step taken meanwhile pans to the edge it leaves through instead of
      // turning the page from where the spread last rested.
      if self.scrollView.isPanningSpread {
        report(restingEdges: [])
      }
    }

    func scrollViewWillEndDragging(
      _ scrollView: UIScrollView,
      withVelocity velocity: CGPoint,
      targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
      targetContentOffset.pointee.x = self.scrollView.spreadRestingOffset(
        forTarget: targetContentOffset.pointee.x
      )
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if !decelerate {
        spreadPanDidSettle()
      }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
      spreadPanDidSettle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
      spreadPanDidSettle()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
      spreadPanDidSettle()
    }
  }
#endif
