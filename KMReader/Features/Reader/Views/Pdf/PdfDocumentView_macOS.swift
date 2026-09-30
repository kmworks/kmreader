#if os(macOS)
  import PDFKit
  import SwiftUI

  struct PdfDocumentView: NSViewRepresentable {
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

    func makeNSView(context: Context) -> PDFView {
      let pdfView = PDFView()
      pdfView.autoScales = true
      pdfView.displaysPageBreaks = false
      pdfView.backgroundColor = .clear

      applyPresentationConfiguration(to: pdfView, coordinator: context.coordinator)
      context.coordinator.bind(pdfView: pdfView)
      loadDocument(into: pdfView, coordinator: context.coordinator)
      return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
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
      // With no new document, an unfinished move's stale target would suppress
      // page reports forever.
      guard let document = PDFDocument(url: documentURL) else {
        coordinator.cancelPositioning()
        return
      }

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

      coordinator.lastResolvedPagePresentation = pagePresentation
      coordinator.lastResolvedReadingDirection = direction
      coordinator.lastResolvedIsolateCoverPage = isolateCoverPage

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

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
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
      private weak var singleClickRecognizer: NSClickGestureRecognizer?
      private weak var doubleClickRecognizer: NSClickGestureRecognizer?
      private weak var longPressRecognizer: NSPressGestureRecognizer?
      private var singleClickWorkItem: DispatchWorkItem?
      private var lastDoubleClickTime: Date = .distantPast
      private var hadSelectionAtClickStart = false

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
        if let existingDoubleClickRecognizer = doubleClickRecognizer {
          if existingDoubleClickRecognizer.view !== pdfView {
            existingDoubleClickRecognizer.view?.removeGestureRecognizer(existingDoubleClickRecognizer)
            pdfView.addGestureRecognizer(existingDoubleClickRecognizer)
          }
        } else {
          let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
          recognizer.numberOfClicksRequired = 2
          recognizer.delegate = self
          pdfView.addGestureRecognizer(recognizer)
          doubleClickRecognizer = recognizer
        }

        if let existingLongPressRecognizer = longPressRecognizer {
          if existingLongPressRecognizer.view !== pdfView {
            existingLongPressRecognizer.view?.removeGestureRecognizer(existingLongPressRecognizer)
            pdfView.addGestureRecognizer(existingLongPressRecognizer)
          }
        } else {
          let recognizer = NSPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
          recognizer.delegate = self
          pdfView.addGestureRecognizer(recognizer)
          longPressRecognizer = recognizer
        }

        if let singleClickRecognizer {
          if singleClickRecognizer.view !== pdfView {
            singleClickRecognizer.view?.removeGestureRecognizer(singleClickRecognizer)
            pdfView.addGestureRecognizer(singleClickRecognizer)
          }
          return
        }

        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleSingleClick(_:)))
        recognizer.numberOfClicksRequired = 1
        recognizer.delegate = self
        pdfView.addGestureRecognizer(recognizer)
        singleClickRecognizer = recognizer
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

      func cancelPositioning() {
        positioningTarget = nil
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
      private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        singleClickWorkItem?.cancel()
        lastDoubleClickTime = Date()
      }

      @objc
      private func handleLongPress(_: NSPressGestureRecognizer) {}

      @objc
      private func handleSingleClick(_ recognizer: NSClickGestureRecognizer) {
        singleClickWorkItem?.cancel()
        if Date().timeIntervalSince(lastDoubleClickTime) < 0.35 { return }

        guard let pdfView = recognizer.view as? PDFView else { return }
        if hadSelectionAtClickStart || pdfView.currentSelection != nil {
          hadSelectionAtClickStart = false
          return
        }

        let size = pdfView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let location = recognizer.location(in: pdfView)
        let normalizedPoint = CGPoint(
          x: max(0, min(1, location.x / size.width)),
          y: max(0, min(1, 1.0 - (location.y / size.height)))
        )

        let item = DispatchWorkItem { [weak self] in
          self?.onSingleTap(normalizedPoint)
        }
        singleClickWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
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

      func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
      ) -> Bool {
        true
      }

      func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
      ) -> Bool {
        gestureRecognizer === singleClickRecognizer && otherGestureRecognizer === longPressRecognizer
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        if gestureRecognizer === singleClickRecognizer || gestureRecognizer === doubleClickRecognizer {
          hadSelectionAtClickStart = (observedPDFView?.currentSelection != nil)
        }
        return true
      }
    }
  }
#endif
