#if os(iOS)
  import PDFKit
  import SwiftUI

  struct PdfDocumentView: UIViewRepresentable {
    let documentURL: URL
    let pagePresentation: PdfPagePresentation
    let isolateCoverPage: Bool
    let readingDirection: ReadingDirection
    let initialPageNumber: Int
    let targetPageNumber: Int?
    let navigationToken: UUID
    let onPageChange: (Int, Int) -> Void
    let onSingleTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(
        onPageChange: onPageChange,
        onSingleTap: onSingleTap
      )
    }

    func makeUIView(context: Context) -> PDFView {
      let pdfView = PDFView()
      pdfView.autoScales = true
      pdfView.displaysPageBreaks = false
      pdfView.backgroundColor = .clear

      applyPresentationConfiguration(to: pdfView, coordinator: context.coordinator)
      context.coordinator.bind(pdfView: pdfView)
      loadDocument(into: pdfView, coordinator: context.coordinator)
      disableScrollInsetAdjustment(in: pdfView)
      return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
      context.coordinator.onPageChange = onPageChange
      context.coordinator.onSingleTap = onSingleTap
      context.coordinator.refreshGestureRecognizers(on: pdfView)

      applyPresentationConfiguration(to: pdfView, coordinator: context.coordinator)

      if context.coordinator.loadedDocumentURL != documentURL {
        loadDocument(into: pdfView, coordinator: context.coordinator)
      } else if context.coordinator.lastNavigationToken != navigationToken {
        context.coordinator.lastNavigationToken = navigationToken
        if let targetPageNumber {
          goToPage(targetPageNumber, in: pdfView)
          scheduleInitialPageCorrection(
            targetPage: targetPageNumber,
            in: pdfView,
            coordinator: context.coordinator
          )
        }
      }
    }

    private func loadDocument(into pdfView: PDFView, coordinator: Coordinator) {
      guard let document = PDFDocument(url: documentURL) else { return }

      // Assigning the document already posts page changes for its first page.
      let clampedInitialPage = max(1, min(initialPageNumber, max(1, document.pageCount)))
      coordinator.beginPositioning(toPage: clampedInitialPage)

      pdfView.document = document
      coordinator.loadedDocumentURL = documentURL

      goToPage(clampedInitialPage, in: pdfView)

      coordinator.lastNavigationToken = navigationToken
      coordinator.notifyPositionedPage(from: pdfView)

      scheduleInitialPageCorrection(
        targetPage: clampedInitialPage,
        in: pdfView,
        coordinator: coordinator
      )
    }

    private func applyPresentationConfiguration(to pdfView: PDFView, coordinator: Coordinator) {
      let direction: ReadingDirection = readingDirection == .webtoon ? .vertical : readingDirection

      if coordinator.lastResolvedPagePresentation == pagePresentation,
        coordinator.lastResolvedReadingDirection == direction,
        coordinator.lastResolvedIsolateCoverPage == isolateCoverPage
      {
        return
      }

      let targetPageAfterConfiguration = currentPageNumber(in: pdfView) ?? initialPageNumber
      let displayMode: PDFDisplayMode

      switch pagePresentation {
      case .auto:
        displayMode = .singlePage
      case .singlePaged:
        displayMode = .singlePage
      case .singleContinuous:
        displayMode = .singlePageContinuous
      case .dualContinuous:
        displayMode = .twoUpContinuous
      }

      pdfView.displayMode = displayMode
      pdfView.displayDirection = direction == .vertical ? .vertical : .horizontal
      pdfView.displaysRTL = direction == .rtl
      pdfView.displaysAsBook = pagePresentation == .dualContinuous && isolateCoverPage
      pdfView.usePageViewController(pagePresentation == .singlePaged, withViewOptions: nil)

      coordinator.lastResolvedPagePresentation = pagePresentation
      coordinator.lastResolvedReadingDirection = direction
      coordinator.lastResolvedIsolateCoverPage = isolateCoverPage

      // usePageViewController rebuilds PDFView's internal view hierarchy, so
      // re-apply the inset lock after every configuration change.
      disableScrollInsetAdjustment(in: pdfView)

      if pdfView.document != nil {
        goToPage(targetPageAfterConfiguration, in: pdfView)
      }

      scheduleInitialPageCorrection(
        targetPage: targetPageAfterConfiguration,
        in: pdfView,
        coordinator: coordinator
      )
    }

    private func goToPage(_ pageNumber: Int, in pdfView: PDFView) {
      guard let document = pdfView.document else { return }
      let index = max(0, min(pageNumber - 1, document.pageCount - 1))
      guard let page = document.page(at: index) else { return }
      let bounds = page.bounds(for: pdfView.displayBox)
      let destination = PDFDestination(
        page: page,
        at: CGPoint(x: bounds.minX, y: bounds.maxY)
      )
      destination.zoom = kPDFDestinationUnspecifiedValue
      pdfView.go(to: destination)
    }

    private func scheduleInitialPageCorrection(
      targetPage: Int,
      in pdfView: PDFView,
      coordinator: Coordinator
    ) {
      // PDFKit may reset current page multiple times during initial layout;
      // retry briefly until the target page sticks.
      let generation = coordinator.beginPositioning(toPage: targetPage)
      let retryDelays: [TimeInterval] = [0.0, 0.05, 0.2, 0.5, 1.0]
      for (index, delay) in retryDelays.enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak pdfView, weak coordinator] in
          guard let pdfView, let coordinator else { return }
          guard coordinator.loadedDocumentURL == documentURL else { return }
          if currentPageNumber(in: pdfView) != targetPage {
            goToPage(targetPage, in: pdfView)
          }
          if index == retryDelays.indices.last {
            coordinator.finishPositioning(generation: generation, in: pdfView)
          }
        }
      }
    }

    private func currentPageNumber(in pdfView: PDFView) -> Int? {
      guard let document = pdfView.document else { return nil }
      guard let page = pdfView.currentPage else { return nil }
      return document.index(for: page) + 1
    }

    // PDFView's internal scroll views use .automatic inset adjustment, so a
    // status bar / safe area change (controls overlay toggles it) shifts the
    // rendered page vertically on iOS 18. Lock all of them to .never.
    private func disableScrollInsetAdjustment(in view: UIView) {
      if let scrollView = view as? UIScrollView {
        scrollView.contentInsetAdjustmentBehavior = .never
      }
      for subview in view.subviews {
        disableScrollInsetAdjustment(in: subview)
      }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var onPageChange: (Int, Int) -> Void
      var onSingleTap: (CGPoint) -> Void
      var loadedDocumentURL: URL?
      var lastNavigationToken: UUID?
      var lastResolvedPagePresentation: PdfPagePresentation?
      var lastResolvedReadingDirection: ReadingDirection?
      var lastResolvedIsolateCoverPage: Bool?
      private weak var observedPDFView: PDFView?
      private var positioningTarget: (page: Int, generation: Int)?
      private var positioningGeneration = 0
      private weak var singleTapRecognizer: UITapGestureRecognizer?
      private weak var doubleTapRecognizer: UITapGestureRecognizer?
      private weak var longPressRecognizer: UILongPressGestureRecognizer?
      private var hadSelectionAtTouchStart = false
      private var singleTapStartPoint: CGPoint?
      private var singleTapStartTime: TimeInterval = 0

      // Stricter than UITapGestureRecognizer's built-in slop: slow/short drags
      // must not toggle the reader overlays. The duration budget includes
      // the wait for the double-tap/long-press failure requirements, so it must
      // stay comfortably above a quick tap's handler delivery latency.
      private let singleTapMaximumMovement: CGFloat = 10
      private let singleTapMaximumDuration: TimeInterval = 0.75

      init(
        onPageChange: @escaping (Int, Int) -> Void,
        onSingleTap: @escaping (CGPoint) -> Void
      ) {
        self.onPageChange = onPageChange
        self.onSingleTap = onSingleTap
        super.init()
      }

      deinit {
        NotificationCenter.default.removeObserver(self)
      }

      func bind(pdfView: PDFView) {
        if let observedPDFView {
          NotificationCenter.default.removeObserver(
            self,
            name: .PDFViewPageChanged,
            object: observedPDFView
          )
        }

        observedPDFView = pdfView
        attachRecognizers(to: pdfView)
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(handlePageChanged),
          name: .PDFViewPageChanged,
          object: pdfView
        )
      }

      func refreshGestureRecognizers(on pdfView: PDFView) {
        attachRecognizers(to: pdfView)
      }

      private func attachRecognizers(to pdfView: PDFView) {
        if let existingDoubleTapRecognizer = doubleTapRecognizer {
          if existingDoubleTapRecognizer.view !== pdfView {
            existingDoubleTapRecognizer.view?.removeGestureRecognizer(existingDoubleTapRecognizer)
            pdfView.addGestureRecognizer(existingDoubleTapRecognizer)
          }
        } else {
          let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
          recognizer.numberOfTapsRequired = 2
          recognizer.cancelsTouchesInView = false
          recognizer.delegate = self
          pdfView.addGestureRecognizer(recognizer)
          doubleTapRecognizer = recognizer
        }

        if let existingLongPressRecognizer = longPressRecognizer {
          if existingLongPressRecognizer.view !== pdfView {
            existingLongPressRecognizer.view?.removeGestureRecognizer(existingLongPressRecognizer)
            pdfView.addGestureRecognizer(existingLongPressRecognizer)
          }
        } else {
          let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
          recognizer.delegate = self
          pdfView.addGestureRecognizer(recognizer)
          longPressRecognizer = recognizer
        }

        if let singleTapRecognizer {
          if singleTapRecognizer.view !== pdfView {
            singleTapRecognizer.view?.removeGestureRecognizer(singleTapRecognizer)
            pdfView.addGestureRecognizer(singleTapRecognizer)
          }
          return
        }

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        recognizer.numberOfTapsRequired = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        if let doubleTapRecognizer {
          recognizer.require(toFail: doubleTapRecognizer)
        }
        if let longPressRecognizer {
          recognizer.require(toFail: longPressRecognizer)
        }
        pdfView.addGestureRecognizer(recognizer)
        singleTapRecognizer = recognizer
      }

      @objc
      private func handlePageChanged() {
        guard let observedPDFView else { return }
        notifyPositionedPage(from: observedPDFView)
      }

      /// Starts moving the view to `page` (document load, presentation change,
      /// or jump). PDFKit resets the current page while it lays out, so until
      /// the move finishes, a page change that lands elsewhere is not the
      /// reader's position and is not reported.
      @discardableResult
      func beginPositioning(toPage page: Int) -> Int {
        positioningGeneration += 1
        positioningTarget = (page, positioningGeneration)
        return positioningGeneration
      }

      /// Ends the move `generation` started, unless a newer one took over, and
      /// reports the page it settled on.
      func finishPositioning(generation: Int, in pdfView: PDFView) {
        guard positioningTarget?.generation == generation else { return }
        positioningTarget = nil
        notifyCurrentPage(from: pdfView)
      }

      func notifyPositionedPage(from pdfView: PDFView) {
        if let positioningTarget, displayedPageNumber(in: pdfView) != positioningTarget.page {
          return
        }
        notifyCurrentPage(from: pdfView)
      }

      private func displayedPageNumber(in pdfView: PDFView) -> Int? {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        return document.index(for: page) + 1
      }

      @objc
      private func handleDoubleTap(_: UITapGestureRecognizer) {}

      @objc
      private func handleLongPress(_: UILongPressGestureRecognizer) {}

      @objc
      private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard let pdfView = recognizer.view as? PDFView else { return }
        if hadSelectionAtTouchStart || pdfView.currentSelection != nil {
          hadSelectionAtTouchStart = false
          return
        }

        if let startPoint = singleTapStartPoint {
          let endPoint = recognizer.location(in: pdfView)
          let movement = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
          let duration = ProcessInfo.processInfo.systemUptime - singleTapStartTime
          singleTapStartPoint = nil
          guard movement <= singleTapMaximumMovement, duration <= singleTapMaximumDuration else { return }
        }

        let size = pdfView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let location = recognizer.location(in: pdfView)
        let normalizedPoint = CGPoint(
          x: max(0, min(1, location.x / size.width)),
          y: max(0, min(1, location.y / size.height))
        )

        onSingleTap(normalizedPoint)
      }

      func notifyCurrentPage(from pdfView: PDFView) {
        guard let document = pdfView.document else {
          onPageChange(1, 0)
          return
        }

        let totalPages = document.pageCount
        guard totalPages > 0 else {
          onPageChange(1, 0)
          return
        }

        guard let currentPage = pdfView.currentPage else {
          onPageChange(1, totalPages)
          return
        }

        let pageNumber = document.index(for: currentPage) + 1
        onPageChange(max(1, pageNumber), totalPages)
      }

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        hadSelectionAtTouchStart = (observedPDFView?.currentSelection != nil)
        // Record the start point in the PDFView's coordinate space, matching
        // the end point measured in handleSingleTap. touch.view is a private
        // subview with its own origin/scroll offset, so mixing the two spaces
        // inflates the movement and rejects every tap.
        if gestureRecognizer === singleTapRecognizer, let pdfView = gestureRecognizer.view {
          singleTapStartPoint = touch.location(in: pdfView)
          singleTapStartTime = touch.timestamp
        }
        return !isInteractiveElement(touch.view)
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        true
      }

      private func isInteractiveElement(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
          if candidate is UIControl {
            return true
          }

          let className = NSStringFromClass(type(of: candidate))
          if className.contains("Button")
            || className.contains("Slider")
            || className.contains("Switch")
            || className.contains("TextField")
            || className.contains("TextView")
            || className.contains("Segmented")
            || className.contains("NavigationBar")
            || className.contains("Toolbar")
            || className.contains("Menu")
            || className.contains("ContextMenu")
            || className.contains("Popover")
          {
            return true
          }

          if candidate.isAccessibilityElement {
            let traits = candidate.accessibilityTraits
            if traits.contains(.button) || traits.contains(.link) {
              return true
            }
          }

          current = candidate.superview
        }

        return false
      }
    }
  }
#endif
