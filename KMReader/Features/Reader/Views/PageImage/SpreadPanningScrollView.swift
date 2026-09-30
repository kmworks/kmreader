//
// SpreadPanningScrollView.swift
//
//

#if os(iOS) || os(tvOS)
  import UIKit

  /// A page host's zoom scroll view that also pans a whole spread at base zoom.
  /// Its pan begins only for horizontal drags the spread can still follow, so
  /// a drag pushing past a spread edge is left to the engine's page turn.
  final class SpreadPanningScrollView: UIScrollView {
    /// Whether the spread's start edge, in reading order, is on the left.
    var spreadStartsAtLeft = true

    /// Edge an animated pan is heading to. It counts as reached while in
    /// flight, so a quick second step turns the page instead of repeating
    /// the pan.
    private var pendingSpreadEdge: ReaderSpreadEdge?

    private static let edgeTolerance: CGFloat = 1

    var isAtBaseZoom: Bool {
      zoomScale <= minimumZoomScale + 0.01
    }

    /// Whether the unzoomed content is a spread wider than the viewport.
    var isPanningSpread: Bool {
      isAtBaseZoom && maxSpreadOffset > 0.5
    }

    /// Edges the spread rests at: none between them, both when it fits.
    var restingSpreadEdges: Set<ReaderSpreadEdge> {
      guard isPanningSpread else { return [.start, .end] }
      if let pendingSpreadEdge {
        return [pendingSpreadEdge]
      }
      var edges: Set<ReaderSpreadEdge> = []
      for edge in [ReaderSpreadEdge.start, .end]
      where abs(contentOffset.x - spreadOffset(for: edge)) <= Self.edgeTolerance {
        edges.insert(edge)
      }
      return edges
    }

    /// The edge closest to the visible part of the spread.
    var nearestSpreadEdge: ReaderSpreadEdge {
      let startDistance = abs(contentOffset.x - spreadOffset(for: .start))
      let endDistance = abs(contentOffset.x - spreadOffset(for: .end))
      return endDistance < startDistance ? .end : .start
    }

    private var maxSpreadOffset: CGFloat {
      max(contentSize.width - bounds.width, 0)
    }

    private func spreadOffset(for edge: ReaderSpreadEdge) -> CGFloat {
      (edge == .start) == spreadStartsAtLeft ? 0 : maxSpreadOffset
    }

    /// Moves the spread to `edge` at once, e.g. when it arrives or the
    /// viewport changes.
    func placeSpread(at edge: ReaderSpreadEdge) {
      pendingSpreadEdge = nil
      let x = isPanningSpread ? spreadOffset(for: edge) : 0
      contentOffset = CGPoint(x: x, y: contentOffset.y)
    }

    /// Pans the spread to `edge` for a navigation command; false when it
    /// already rests or is heading there.
    @discardableResult
    func panSpread(to edge: ReaderSpreadEdge, animated: Bool) -> Bool {
      guard isPanningSpread, pendingSpreadEdge != edge else { return false }
      let target = CGPoint(x: spreadOffset(for: edge), y: contentOffset.y)
      guard abs(contentOffset.x - target.x) > 0.5 else {
        pendingSpreadEdge = nil
        return false
      }
      pendingSpreadEdge = animated ? edge : nil
      setContentOffset(target, animated: animated)
      return true
    }

    /// Ends a command pan once it lands or a drag takes over.
    func clearPendingSpreadPan() {
      pendingSpreadEdge = nil
    }

    /// Whether a horizontal drag of `translationX` would pan the spread rather
    /// than push past its edge.
    func canPanSpread(forHorizontalDrag translationX: CGFloat) -> Bool {
      guard isPanningSpread, translationX != 0 else { return false }
      // Dragging left reveals the content on the right.
      if translationX < 0 {
        return contentOffset.x < maxSpreadOffset - Self.edgeTolerance
      }
      return contentOffset.x > Self.edgeTolerance
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard gestureRecognizer === panGestureRecognizer, isPanningSpread else {
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
      }
      guard let dragX = panGestureRecognizer.horizontalDrag(in: self),
        canPanSpread(forHorizontalDrag: dragX)
      else {
        return false
      }
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
  }
#endif
