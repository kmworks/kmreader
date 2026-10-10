//
// WebPubPagedCoverView.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit

  struct WebPubPagedCoverView: UIViewControllerRepresentable {
    @Bindable var viewModel: EpubReaderViewModel
    let preferences: EpubThemePreferences
    let colorScheme: ColorScheme
    let animateTapTurns: Bool
    let overlayPreferences: EpubOverlayPreferences
    let showingControls: Bool
    let bookTitle: String?
    let onCenterTap: () -> Void
    let onEndReached: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CoverEpubContainerViewController {
      let container = CoverEpubContainerViewController()
      container.coordinator = context.coordinator
      context.coordinator.containerViewController = container

      let initialChapterIndex = viewModel.currentChapterIndex
      let initialPageCount = viewModel.chapterPageCount(at: initialChapterIndex) ?? 1
      let initialPageIndex = max(0, min(viewModel.currentPageIndex, initialPageCount - 1))

      if let initialVC = context.coordinator.makeChapterViewController(
        chapterIndex: initialChapterIndex,
        subPageIndex: initialPageIndex
      ) {
        context.coordinator.installDeck(
          around: initialVC,
          chapterIndex: initialChapterIndex,
          subPageIndex: initialPageIndex
        )
        context.coordinator.commitLocation(
          chapterIndex: initialChapterIndex,
          pageIndex: initialPageIndex,
          notify: false
        )
      }

      return container
    }

    func updateUIViewController(_ container: CoverEpubContainerViewController, context: Context) {
      context.coordinator.parent = self
      context.coordinator.containerViewController = container
      defer { context.coordinator.hasCompletedInitialUpdate = true }

      let initialChapterIndex = viewModel.currentChapterIndex
      let initialPageCount = viewModel.chapterPageCount(at: initialChapterIndex) ?? 1
      let initialPageIndex = max(0, min(viewModel.currentPageIndex, initialPageCount - 1))

      if context.coordinator.currentController == nil,
        initialChapterIndex >= 0,
        initialChapterIndex < viewModel.chapterCount,
        let initialVC = context.coordinator.makeChapterViewController(
          chapterIndex: initialChapterIndex,
          subPageIndex: initialPageIndex
        )
      {
        context.coordinator.installDeck(
          around: initialVC,
          chapterIndex: initialChapterIndex,
          subPageIndex: initialPageIndex
        )
        context.coordinator.commitLocation(
          chapterIndex: initialChapterIndex,
          pageIndex: initialPageIndex,
          notify: false
        )
      }

      if let targetChapterIndex = viewModel.targetChapterIndex,
        let targetPageIndex = viewModel.targetPageIndex,
        !context.coordinator.isAnimating,
        context.coordinator.session == nil,
        targetChapterIndex >= 0,
        targetChapterIndex < viewModel.chapterCount,
        targetChapterIndex != context.coordinator.currentChapterIndex
          || targetPageIndex != context.coordinator.currentPageIndex
      {
        let pageCount = viewModel.chapterPageCount(at: targetChapterIndex) ?? 1
        let isLastPageRequest = targetPageIndex < 0
        let normalizedPageIndex =
          isLastPageRequest
          ? max(0, pageCount - 1)
          : max(0, min(targetPageIndex, pageCount - 1))

        if let target = context.coordinator.prepareTurnTarget(
          chapterIndex: targetChapterIndex,
          subPageIndex: normalizedPageIndex,
          preferLastPageOnReady: isLastPageRequest
        ) {
          let shouldAnimate = context.coordinator.hasCompletedInitialUpdate && animateTapTurns
          if shouldAnimate {
            context.coordinator.animateTransition(to: target)
          } else {
            context.coordinator.installDeck(
              around: target.host,
              chapterIndex: target.chapterIndex,
              subPageIndex: target.subPageIndex
            )
            context.coordinator.commitLocation(
              chapterIndex: target.chapterIndex,
              pageIndex: target.subPageIndex,
              notify: true
            )
          }
        }
      }

      context.coordinator.reconfigureHosts()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var parent: WebPubPagedCoverView
      var currentChapterIndex: Int
      var currentPageIndex: Int
      var isAnimating = false
      var hasCompletedInitialUpdate = false
      weak var containerViewController: CoverEpubContainerViewController?

      private(set) var currentController: EpubPageViewController?
      private var nextController: EpubPageViewController?
      private var previousController: EpubPageViewController?

      private var panRecognizer: UIPanGestureRecognizer?
      private var tapRecognizer: UITapGestureRecognizer?
      private var longPressRecognizer: UILongPressGestureRecognizer?

      enum SlideDirection {
        case forward
        case backward
      }

      struct TurnTarget {
        let host: EpubPageViewController
        let chapterIndex: Int
        let subPageIndex: Int
        let isCrossChapter: Bool
        let isForward: Bool
      }

      private(set) var session: SlideSession?

      struct SlideSession {
        let direction: SlideDirection
        let target: TurnTarget
        let originPage: Int
        let overlay: UIView
        var offset: CGFloat = 0
      }

      private var rubberOffset: CGFloat = 0
      private var lastLayoutSize: CGSize = .zero

      private enum Metrics {
        static let minimumDragDistance: CGFloat = 1
        static let directionalDragBias: CGFloat = 4
        static let overscrollResistance: CGFloat = 0.2
        static let cancelThreshold: CGFloat = 0.5
        static let commitDistanceRatio: CGFloat = 0.18
        static let commitVelocityThreshold: CGFloat = 700
        static let movingShadowOpacity: Float = 0.12
        static let idleShadowOpacity: Float = 0.05
        static let movingShadowRadius: CGFloat = 5
        static let idleShadowRadius: CGFloat = 2
        static let movingShadowOffset: CGFloat = 3
        static let idleShadowOffset: CGFloat = 1
        static let animationDuration: TimeInterval = 0.3
      }

      private var paginationLayout: WebPubPaginationLayout {
        WebPubPaginationLayout.resolve(
          language: parent.viewModel.publicationLanguage,
          readingProgression: parent.viewModel.publicationReadingProgression
        )
      }

      private var forwardDragSign: CGFloat {
        paginationLayout.reversesHorizontalGestureDirection ? 1 : -1
      }

      private var backwardDragSign: CGFloat {
        -forwardDragSign
      }

      init(_ parent: WebPubPagedCoverView) {
        self.parent = parent
        self.currentChapterIndex = parent.viewModel.currentChapterIndex
        self.currentPageIndex = parent.viewModel.currentPageIndex
        super.init()
      }

      func setupGestures(on view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        panRecognizer = pan

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
        tapRecognizer = tap

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.cancelsTouchesInView = false
        longPress.delegate = self
        tap.require(toFail: longPress)
        tap.require(toFail: pan)
        view.addGestureRecognizer(longPress)
        longPressRecognizer = longPress
        pan.require(toFail: longPress)
      }

      // MARK: - Chapter hosts

      func makeChapterViewController(
        chapterIndex: Int,
        subPageIndex: Int,
        preferLastPageOnReady: Bool = false
      ) -> EpubPageViewController? {
        guard chapterIndex >= 0, chapterIndex < parent.viewModel.chapterCount else { return nil }
        let pageCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
        if !preferLastPageOnReady {
          guard subPageIndex >= 0, subPageIndex < pageCount else { return nil }
        } else {
          guard subPageIndex >= 0 else { return nil }
        }

        let containerInsets = parent.viewModel.containerInsetsForLabels().uiEdgeInsets
        let theme = parent.preferences.resolvedTheme(for: parent.colorScheme)
        let fontPath = parent.preferences.fontFamily.fontName.flatMap {
          CustomFontStore.shared.getFontPath(for: $0)
        }
        let chapterURL = parent.viewModel.chapterURL(at: chapterIndex)
        let chapterMediaType = parent.viewModel.chapterMediaType(at: chapterIndex)
        let rootURL = parent.viewModel.resourceRootURL
        let readiumPayload = parent.preferences.makeReadiumPayload(
          theme: theme,
          fontPath: fontPath,
          rootURL: rootURL,
          viewportSize: parent.viewModel.resolvedViewportSize
        )
        let chapterIndexForCallback = chapterIndex
        let onPageCountReady: (Int) -> Void = { [weak viewModel = parent.viewModel] pageCount in
          Task { @MainActor in
            viewModel?.updateChapterPageCount(pageCount, for: chapterIndexForCallback)
          }
        }

        let locationPageIndex = min(max(subPageIndex, 0), max(0, pageCount - 1))
        guard
          let location = parent.viewModel.pageLocation(
            chapterIndex: chapterIndex,
            pageIndex: locationPageIndex
          )
        else { return nil }
        let chapterProgress =
          location.pageCount > 0 ? Double(location.pageIndex + 1) / Double(location.pageCount) : nil
        let totalProgression = parent.viewModel.totalProgression(
          location: location,
          chapterProgress: chapterProgress
        )
        let initialProgression = parent.viewModel.initialProgression(for: chapterIndex)

        let controller = EpubPageViewController(
          chapterURL: chapterURL,
          chapterMediaType: chapterMediaType,
          rootURL: rootURL,
          mediaTypesByRelativePath: parent.viewModel.mediaTypesByRelativePath,
          containerInsets: containerInsets,
          theme: theme,
          contentCSS: readiumPayload.css,
          readiumProperties: readiumPayload.properties,
          publicationLanguage: parent.viewModel.publicationLanguage,
          publicationReadingProgression: parent.viewModel.publicationReadingProgression,
          chapterIndex: chapterIndex,
          subPageIndex: subPageIndex,
          totalPages: pageCount,
          bookTitle: parent.bookTitle,
          chapterTitle: location.title,
          totalProgression: totalProgression,
          overlayPreferences: parent.overlayPreferences,
          showingControls: parent.showingControls,
          labelTopOffset: parent.viewModel.labelTopOffset,
          labelBottomOffset: parent.viewModel.labelBottomOffset,
          useSafeArea: parent.viewModel.useSafeArea,
          onPageCountReady: onPageCountReady
        )
        controller.preferLastPageOnReady = preferLastPageOnReady
        controller.targetProgressionOnReady = initialProgression
        wireController(controller)
        controller.onLinkTap = { [weak self] url in
          self?.parent.viewModel.navigateToURL(url)
        }
        controller.loadViewIfNeeded()
        return controller
      }

      private func wireController(_ controller: EpubPageViewController) {
        controller.onPageIndexAdjusted = { [weak self, weak controller] pageIndex in
          guard let self, let controller else { return }
          guard self.currentController === controller, self.session == nil else { return }
          let chapterIndex = controller.chapterIndex
          let storedCount = self.parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
          let effectiveCount = max(storedCount, controller.totalPagesInChapter)
          let normalizedPageIndex = max(0, min(pageIndex, effectiveCount - 1))
          if effectiveCount != storedCount {
            self.parent.viewModel.updateChapterPageCount(effectiveCount, for: chapterIndex)
          }
          self.parent.viewModel.currentChapterIndex = chapterIndex
          self.parent.viewModel.currentPageIndex = normalizedPageIndex
          self.currentChapterIndex = chapterIndex
          self.currentPageIndex = normalizedPageIndex
          self.parent.viewModel.pageDidChange()
        }
      }

      private func reconfigureHost(_ controller: EpubPageViewController) {
        let chapterIndex = controller.chapterIndex
        let containerInsets = parent.viewModel.containerInsetsForLabels().uiEdgeInsets
        let theme = parent.preferences.resolvedTheme(for: parent.colorScheme)
        let fontPath = parent.preferences.fontFamily.fontName.flatMap {
          CustomFontStore.shared.getFontPath(for: $0)
        }
        let readiumPayload = parent.preferences.makeReadiumPayload(
          theme: theme,
          fontPath: fontPath,
          rootURL: parent.viewModel.resourceRootURL,
          viewportSize: parent.viewModel.resolvedViewportSize
        )

        guard
          let location = parent.viewModel.pageLocation(
            chapterIndex: chapterIndex,
            pageIndex: controller.currentSubPageIndex
          )
        else { return }
        let chapterProgress =
          location.pageCount > 0 ? Double(location.pageIndex + 1) / Double(location.pageCount) : nil
        let totalProgression = parent.viewModel.totalProgression(
          location: location,
          chapterProgress: chapterProgress
        )

        controller.configure(
          chapterURL: parent.viewModel.chapterURL(at: chapterIndex),
          chapterMediaType: parent.viewModel.chapterMediaType(at: chapterIndex),
          rootURL: parent.viewModel.resourceRootURL,
          mediaTypesByRelativePath: parent.viewModel.mediaTypesByRelativePath,
          containerInsets: containerInsets,
          theme: theme,
          contentCSS: readiumPayload.css,
          readiumProperties: readiumPayload.properties,
          publicationLanguage: parent.viewModel.publicationLanguage,
          publicationReadingProgression: parent.viewModel.publicationReadingProgression,
          chapterIndex: chapterIndex,
          subPageIndex: controller.currentSubPageIndex,
          totalPages: controller.totalPagesInChapter,
          bookTitle: parent.bookTitle,
          chapterTitle: location.title,
          totalProgression: totalProgression,
          overlayPreferences: parent.overlayPreferences,
          showingControls: parent.showingControls,
          labelTopOffset: parent.viewModel.labelTopOffset,
          labelBottomOffset: parent.viewModel.labelBottomOffset,
          useSafeArea: parent.viewModel.useSafeArea,
          onPageCountReady: { [weak viewModel = parent.viewModel] pageCount in
            Task { @MainActor in
              viewModel?.updateChapterPageCount(pageCount, for: chapterIndex)
            }
          }
        )
      }

      func reconfigureHosts() {
        if let currentController { reconfigureHost(currentController) }
        if let nextController { reconfigureHost(nextController) }
        if let previousController { reconfigureHost(previousController) }
      }

      // MARK: - Deck management

      func installDeck(
        around controller: EpubPageViewController,
        chapterIndex: Int,
        subPageIndex: Int
      ) {
        guard let container = containerViewController else { return }

        let detached = [currentController, nextController, previousController]
          .compactMap { $0 }
          .filter { $0 !== controller }
        for host in detached {
          removeChildController(host, from: container)
        }
        nextController = nil
        previousController = nil

        currentController = controller
        addChildController(controller, to: container)
        controller.view.frame = container.view.bounds
        controller.view.isHidden = false
        controller.view.layer.zPosition = 1
        updateShadow(for: controller.view, isElevated: true, offset: 0)
        if controller.currentSubPageIndex != subPageIndex {
          controller.scrollToPageIndex(subPageIndex)
        }

        prepareNeighbors(
          chapterIndex: chapterIndex,
          subPageIndex: subPageIndex,
          reusing: detached
        )
      }

      private func prepareNeighbors(
        chapterIndex: Int,
        subPageIndex: Int,
        reusing: [EpubPageViewController] = []
      ) {
        guard let container = containerViewController else { return }

        if let nextTarget = nextPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex),
          nextTarget.chapterIndex != chapterIndex
        {
          if nextController?.chapterIndex != nextTarget.chapterIndex {
            removeChildController(nextController, from: container)
            nextController = nil
            let reused = reusing.first { $0.chapterIndex == nextTarget.chapterIndex }
            if let host = reused
              ?? makeChapterViewController(
                chapterIndex: nextTarget.chapterIndex,
                subPageIndex: nextTarget.subPageIndex,
                preferLastPageOnReady: nextTarget.preferLastPage
              )
            {
              if host.currentSubPageIndex != nextTarget.subPageIndex, !nextTarget.preferLastPage {
                host.scrollToPageIndex(nextTarget.subPageIndex)
              }
              nextController = host
              adoptNeighbor(host, in: container)
            }
          }
        } else {
          removeChildController(nextController, from: container)
          nextController = nil
        }

        if let prevTarget = previousPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex),
          prevTarget.chapterIndex != chapterIndex
        {
          if previousController?.chapterIndex != prevTarget.chapterIndex {
            removeChildController(previousController, from: container)
            previousController = nil
            let reused = reusing.first { $0.chapterIndex == prevTarget.chapterIndex }
            if let host = reused
              ?? makeChapterViewController(
                chapterIndex: prevTarget.chapterIndex,
                subPageIndex: prevTarget.subPageIndex,
                preferLastPageOnReady: prevTarget.preferLastPage
              )
            {
              if host.currentSubPageIndex != prevTarget.subPageIndex, !prevTarget.preferLastPage {
                host.scrollToPageIndex(prevTarget.subPageIndex)
              }
              previousController = host
              adoptNeighbor(host, in: container)
            }
          }
        } else {
          removeChildController(previousController, from: container)
          previousController = nil
        }
      }

      private func adoptNeighbor(_ host: EpubPageViewController, in container: UIViewController) {
        reconfigureHost(host)
        addChildController(host, to: container)
        host.view.frame = container.view.bounds
        // Hidden web views get their rAF-driven pagination stalled until revealed,
        // so neighbors stay compositing underneath the opaque current page.
        host.view.isHidden = false
        host.view.layer.zPosition = 0
        host.loadViewIfNeeded()
        host.forceEnsureContentLoaded()
      }

      private func addChildController(_ child: EpubPageViewController, to parent: UIViewController) {
        guard child.parent !== parent else { return }
        if child.parent != nil {
          child.willMove(toParent: nil)
          child.view.removeFromSuperview()
          child.removeFromParent()
        }
        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: parent)
      }

      private func removeChildController(_ child: EpubPageViewController?, from parent: UIViewController) {
        guard let child, child.parent === parent else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
      }

      private func nextPageTarget(
        chapterIndex: Int,
        subPageIndex: Int
      ) -> (chapterIndex: Int, subPageIndex: Int, preferLastPage: Bool)? {
        let storedCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
        if subPageIndex < storedCount - 1 {
          return (chapterIndex, subPageIndex + 1, false)
        }
        let nextChapter = chapterIndex + 1
        if nextChapter < parent.viewModel.chapterCount {
          return (nextChapter, 0, false)
        }
        return nil
      }

      private func previousPageTarget(
        chapterIndex: Int,
        subPageIndex: Int
      ) -> (chapterIndex: Int, subPageIndex: Int, preferLastPage: Bool)? {
        if subPageIndex > 0 {
          return (chapterIndex, subPageIndex - 1, false)
        }
        let previousChapter = chapterIndex - 1
        guard previousChapter >= 0 else { return nil }
        let previousCount = parent.viewModel.chapterPageCount(at: previousChapter) ?? 1
        return (previousChapter, max(0, previousCount - 1), previousCount <= 1)
      }

      func prepareTurnTarget(
        chapterIndex: Int,
        subPageIndex: Int,
        preferLastPageOnReady: Bool
      ) -> TurnTarget? {
        guard let current = currentController else { return nil }
        let isForward =
          chapterIndex > currentChapterIndex
          || (chapterIndex == currentChapterIndex && subPageIndex > currentPageIndex)
        if chapterIndex == current.chapterIndex {
          return TurnTarget(
            host: current,
            chapterIndex: chapterIndex,
            subPageIndex: subPageIndex,
            isCrossChapter: false,
            isForward: isForward
          )
        }
        let neighbor: EpubPageViewController?
        if nextController?.chapterIndex == chapterIndex {
          neighbor = nextController
        } else if previousController?.chapterIndex == chapterIndex {
          neighbor = previousController
        } else {
          neighbor = nil
        }
        guard
          let host = neighbor
            ?? makeChapterViewController(
              chapterIndex: chapterIndex,
              subPageIndex: subPageIndex,
              preferLastPageOnReady: preferLastPageOnReady
            )
        else { return nil }
        if host.currentSubPageIndex != subPageIndex, !preferLastPageOnReady {
          host.scrollToPageIndex(subPageIndex)
        }
        return TurnTarget(
          host: host,
          chapterIndex: chapterIndex,
          subPageIndex: subPageIndex,
          isCrossChapter: true,
          isForward: isForward
        )
      }

      func commitLocation(chapterIndex: Int, pageIndex: Int, notify: Bool) {
        currentChapterIndex = chapterIndex
        currentPageIndex = pageIndex
        guard notify else {
          if parent.viewModel.currentChapterIndex != chapterIndex {
            parent.viewModel.currentChapterIndex = chapterIndex
          }
          if parent.viewModel.currentPageIndex != pageIndex {
            parent.viewModel.currentPageIndex = pageIndex
          }
          return
        }
        Task { @MainActor in
          parent.viewModel.currentChapterIndex = chapterIndex
          parent.viewModel.currentPageIndex = pageIndex
          parent.viewModel.targetChapterIndex = nil
          parent.viewModel.targetPageIndex = nil
          parent.viewModel.pageDidChange()
        }
      }

      // MARK: - Slide sessions

      private func beginSlideSession(direction: SlideDirection, target: TurnTarget) -> Bool {
        guard session == nil else { return false }
        guard let container = containerViewController, let current = currentController else { return false }
        rubberOffset = 0
        current.view.frame = container.view.bounds
        current.view.layoutIfNeeded()
        // A reused neighbor host can sit on a stale page after mid-chapter jumps.
        if target.isCrossChapter, target.host.currentSubPageIndex != target.subPageIndex {
          target.host.scrollToPageIndex(target.subPageIndex)
        }

        let overlay: UIView
        if let snapshot = current.view.snapshotView(afterScreenUpdates: false) {
          overlay = snapshot
        } else if let image = current.makeBacksideSnapshotImage() {
          overlay = UIImageView(image: image)
          overlay.contentMode = .scaleToFill
        } else {
          return false
        }
        overlay.frame = container.view.bounds
        overlay.isUserInteractionEnabled = false

        container.view.addSubview(overlay)
        let width = container.view.bounds.width

        switch direction {
        case .forward:
          if target.isCrossChapter {
            addChildController(target.host, to: container)
            target.host.view.frame = container.view.bounds
            target.host.view.layer.zPosition = 1
            current.view.isHidden = true
            current.view.layer.zPosition = 0
          } else {
            current.scrollToPageIndex(target.subPageIndex)
          }
          overlay.layer.zPosition = 2
          updateShadow(for: overlay, isElevated: true, offset: 0)
        case .backward:
          overlay.layer.zPosition = 1
          updateShadow(for: overlay, isElevated: false, offset: 0)
          if target.isCrossChapter {
            addChildController(target.host, to: container)
            current.view.isHidden = true
            current.view.layer.zPosition = 0
          } else {
            current.scrollToPageIndex(target.subPageIndex)
          }
          target.host.view.frame = container.view.bounds.offsetBy(dx: -backwardDragSign * width, dy: 0)
          target.host.view.layer.zPosition = 2
          updateShadow(for: target.host.view, isElevated: true, offset: -backwardDragSign * width)
        }

        session = SlideSession(
          direction: direction,
          target: target,
          originPage: currentPageIndex,
          overlay: overlay
        )
        return true
      }

      private func layoutSession(offset: CGFloat) {
        guard let session, let container = containerViewController else { return }
        let width = container.view.bounds.width
        switch session.direction {
        case .forward:
          session.overlay.frame = container.view.bounds.offsetBy(dx: offset, dy: 0)
          updateShadow(for: session.overlay, isElevated: true, offset: offset)
        case .backward:
          let dx = offset - backwardDragSign * width
          session.target.host.view.frame = container.view.bounds.offsetBy(dx: dx, dy: 0)
          updateShadow(for: session.target.host.view, isElevated: true, offset: dx)
        }
      }

      private func settleSession(commit: Bool, animated: Bool) {
        guard let session, let container = containerViewController else { return }
        isAnimating = true
        let width = container.view.bounds.width

        let targetFrame: CGRect
        let shadowedView: UIView
        let shadowOffset: CGFloat
        switch (session.direction, commit) {
        case (.forward, true):
          targetFrame = container.view.bounds.offsetBy(dx: forwardDragSign * width, dy: 0)
          shadowedView = session.overlay
          shadowOffset = forwardDragSign * width
        case (.forward, false):
          targetFrame = container.view.bounds
          shadowedView = session.overlay
          shadowOffset = 0
        case (.backward, true):
          targetFrame = container.view.bounds
          shadowedView = session.target.host.view
          shadowOffset = 0
        case (.backward, false):
          targetFrame = container.view.bounds.offsetBy(dx: -backwardDragSign * width, dy: 0)
          shadowedView = session.target.host.view
          shadowOffset = -backwardDragSign * width
        }

        let finish = {
          self.finishSlideSession(commit: commit)
        }
        guard animated else {
          shadowedView.frame = targetFrame
          updateShadow(for: shadowedView, isElevated: true, offset: shadowOffset)
          finish()
          return
        }
        UIView.animate(
          withDuration: Metrics.animationDuration,
          delay: 0,
          options: [.curveEaseOut]
        ) {
          shadowedView.frame = targetFrame
          self.updateShadow(for: shadowedView, isElevated: true, offset: shadowOffset)
        } completion: { _ in
          finish()
        }
      }

      private func finishSlideSession(commit: Bool) {
        guard let session, let container = containerViewController else { return }
        let target = session.target

        if commit {
          session.overlay.removeFromSuperview()
          self.session = nil
          if target.isCrossChapter {
            installDeck(
              around: target.host,
              chapterIndex: target.chapterIndex,
              subPageIndex: target.subPageIndex
            )
          } else {
            resetCurrentPresentation()
            prepareNeighbors(
              chapterIndex: target.chapterIndex,
              subPageIndex: target.subPageIndex
            )
          }
          isAnimating = false
          commitLocation(
            chapterIndex: target.chapterIndex,
            pageIndex: target.subPageIndex,
            notify: true
          )
        } else {
          let overlay = session.overlay
          let resetPresentation = {
            if let current = self.currentController {
              current.view.frame = container.view.bounds
              current.view.isHidden = false
              current.view.layer.zPosition = 1
              self.updateShadow(for: current.view, isElevated: true, offset: 0)
            }
            overlay.removeFromSuperview()
          }
          if target.isCrossChapter {
            resetPresentation()
          } else if let current = currentController {
            // The live view still shows the target page; restore it only after the scroll-back lands.
            current.scrollToPageIndex(session.originPage, completion: resetPresentation)
          } else {
            resetPresentation()
          }
          if target.isCrossChapter {
            if target.host === nextController || target.host === previousController {
              target.host.view.layer.zPosition = 0
              target.host.view.frame = container.view.bounds
            } else {
              removeChildController(target.host, from: container)
            }
          }
          self.session = nil
          isAnimating = false
        }
      }

      private func resetCurrentPresentation() {
        guard let container = containerViewController, let current = currentController else { return }
        current.view.frame = container.view.bounds
        current.view.isHidden = false
        current.view.layer.zPosition = 1
        updateShadow(for: current.view, isElevated: true, offset: 0)
      }

      func animateTransition(to target: TurnTarget) {
        let direction: SlideDirection = target.isForward ? .forward : .backward
        guard beginSlideSession(direction: direction, target: target) else {
          installDeck(
            around: target.host,
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex
          )
          commitLocation(
            chapterIndex: target.chapterIndex,
            pageIndex: target.subPageIndex,
            notify: true
          )
          return
        }
        settleSession(commit: true, animated: true)
      }

      func handleContainerLayout() {
        guard let container = containerViewController else { return }
        let size = container.view.bounds.size
        guard size.width > 0, size.height > 0, size != lastLayoutSize else { return }
        lastLayoutSize = size
        if session != nil {
          settleSession(commit: false, animated: false)
        }
        guard let current = currentController else { return }
        current.view.frame = container.view.bounds
        nextController?.view.frame = container.view.bounds
        previousController?.view.frame = container.view.bounds
      }

      private func updateShadow(for view: UIView?, isElevated: Bool, offset: CGFloat) {
        guard let view else { return }
        guard isElevated else {
          view.layer.shadowOpacity = 0
          return
        }

        let isMoving = abs(offset) > Metrics.cancelThreshold
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = isMoving ? Metrics.movingShadowOpacity : Metrics.idleShadowOpacity
        view.layer.shadowRadius = isMoving ? Metrics.movingShadowRadius : Metrics.idleShadowRadius
        view.layer.shadowOffset = CGSize(
          width: isMoving ? (offset < 0 ? Metrics.movingShadowOffset : -Metrics.movingShadowOffset) : 0,
          height: Metrics.idleShadowOffset
        )
      }

      // MARK: - Gestures

      @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard !isAnimating else { return }
        guard let view = recognizer.view else { return }

        switch recognizer.state {
        case .changed:
          let translation = recognizer.translation(in: view)
          handlePanChanged(translation: translation, viewWidth: view.bounds.width)
        case .ended:
          let translation = recognizer.translation(in: view)
          let velocity = recognizer.velocity(in: view)
          handlePanEnded(translation: translation, velocity: velocity, viewWidth: view.bounds.width)
        case .cancelled, .failed:
          cancelPan()
        default:
          break
        }
      }

      private func handlePanChanged(translation: CGPoint, viewWidth: CGFloat) {
        guard currentController != nil else { return }
        guard abs(translation.x) > abs(translation.y) + Metrics.directionalDragBias else { return }
        guard abs(translation.x) > Metrics.minimumDragDistance else { return }

        if var session {
          let clamped = clampSessionOffset(
            translation.x,
            direction: session.direction,
            viewWidth: viewWidth
          )
          session.offset = clamped
          self.session = session
          layoutSession(offset: clamped)
          return
        }

        let directionOffset = pageTurnDirectionOffset(for: translation.x)
        let direction: SlideDirection = directionOffset == 1 ? .forward : .backward
        guard let target = dragTarget(direction: direction) else {
          rubberOffset = translation.x * Metrics.overscrollResistance
          layoutRubberband()
          return
        }
        if beginSlideSession(direction: direction, target: target) {
          let clamped = clampSessionOffset(translation.x, direction: direction, viewWidth: viewWidth)
          session?.offset = clamped
          layoutSession(offset: clamped)
        } else {
          rubberOffset = translation.x * Metrics.overscrollResistance
          layoutRubberband()
        }
      }

      private func handlePanEnded(translation: CGPoint, velocity: CGPoint, viewWidth: CGFloat) {
        guard abs(translation.x) > abs(translation.y) + Metrics.directionalDragBias else {
          cancelPan()
          return
        }

        if session != nil {
          let shouldCommit =
            abs(translation.x) > viewWidth * Metrics.commitDistanceRatio
            || abs(velocity.x) > Metrics.commitVelocityThreshold
          settleSession(commit: shouldCommit, animated: true)
          return
        }

        if abs(rubberOffset) > Metrics.cancelThreshold {
          isAnimating = true
          UIView.animate(
            withDuration: Metrics.animationDuration,
            delay: 0,
            options: [.curveEaseOut]
          ) {
            self.currentController?.view.frame = self.containerViewController?.view.bounds ?? .zero
            self.updateShadow(for: self.currentController?.view, isElevated: true, offset: 0)
          } completion: { _ in
            self.rubberOffset = 0
            self.isAnimating = false
          }
        } else {
          cancelPan()
        }
      }

      private func cancelPan() {
        if session != nil {
          settleSession(commit: false, animated: true)
          return
        }
        rubberOffset = 0
        resetCurrentPresentation()
      }

      private func layoutRubberband() {
        guard let container = containerViewController else { return }
        currentController?.view.frame = container.view.bounds.offsetBy(dx: rubberOffset, dy: 0)
        updateShadow(for: currentController?.view, isElevated: true, offset: rubberOffset)
      }

      private func dragTarget(direction: SlideDirection) -> TurnTarget? {
        guard let current = currentController else { return nil }
        let chapterIndex = current.chapterIndex
        let subPageIndex = currentPageIndex
        switch direction {
        case .forward:
          guard let target = nextPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex)
          else { return nil }
          if target.chapterIndex == chapterIndex {
            return TurnTarget(
              host: current,
              chapterIndex: chapterIndex,
              subPageIndex: target.subPageIndex,
              isCrossChapter: false,
              isForward: true
            )
          }
          let host =
            nextController
            ?? makeChapterViewController(
              chapterIndex: target.chapterIndex,
              subPageIndex: target.subPageIndex,
              preferLastPageOnReady: target.preferLastPage
            )
          guard let host else { return nil }
          return TurnTarget(
            host: host,
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            isCrossChapter: true,
            isForward: true
          )
        case .backward:
          guard let target = previousPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex)
          else { return nil }
          if target.chapterIndex == chapterIndex {
            return TurnTarget(
              host: current,
              chapterIndex: chapterIndex,
              subPageIndex: target.subPageIndex,
              isCrossChapter: false,
              isForward: false
            )
          }
          let host =
            previousController
            ?? makeChapterViewController(
              chapterIndex: target.chapterIndex,
              subPageIndex: target.subPageIndex,
              preferLastPageOnReady: target.preferLastPage
            )
          guard let host else { return nil }
          return TurnTarget(
            host: host,
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            isCrossChapter: true,
            isForward: false
          )
        }
      }

      private func pageTurnDirectionOffset(for translationX: CGFloat) -> Int {
        translationX * forwardDragSign > 0 ? 1 : -1
      }

      private func clampSessionOffset(
        _ translationX: CGFloat,
        direction: SlideDirection,
        viewWidth: CGFloat
      ) -> CGFloat {
        guard viewWidth > 0 else { return 0 }
        switch direction {
        case .forward:
          return forwardDragSign * min(max(0, translationX * forwardDragSign), viewWidth)
        case .backward:
          return backwardDragSign * min(max(0, translationX * backwardDragSign), viewWidth)
        }
      }

      // MARK: - Tap Handling

      @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard !isAnimating else { return }
        let location = recognizer.location(in: recognizer.view)
        let size = recognizer.view?.bounds.size ?? .zero
        guard size.width > 0, size.height > 0 else { return }

        let normalizedX = location.x / size.width
        let normalizedY = location.y / size.height

        let action = TapZoneHelper.action(
          normalizedX: normalizedX,
          normalizedY: normalizedY,
          tapZoneMode: AppConfig.epubTapZoneMode,
          tapZoneInversionMode: AppConfig.epubTapZoneInversionMode,
          readingDirection: tapReadingDirection()
        )

        switch action {
        case .previous:
          parent.viewModel.goToPreviousPage()
        case .next:
          if isAtLastPage() {
            parent.onEndReached()
          } else {
            parent.viewModel.goToNextPage()
          }
        case .toggleControls:
          parent.onCenterTap()
        }
      }

      @objc func handleLongPress(_: UILongPressGestureRecognizer) {}

      private func tapReadingDirection() -> ReadingDirection {
        switch parent.viewModel.publicationReadingProgression {
        case .rtl:
          return .rtl
        case .ttb, .btt:
          return .vertical
        case .ltr, .auto, .none:
          return .ltr
        }
      }

      private func isAtLastPage() -> Bool {
        guard let current = currentController else { return false }
        let lastChapterIndex = parent.viewModel.chapterCount - 1
        guard current.chapterIndex == lastChapterIndex else { return false }
        let storedCount = parent.viewModel.chapterPageCount(at: lastChapterIndex) ?? 1
        let pageCount = max(storedCount, current.totalPagesInChapter)
        return currentPageIndex >= pageCount - 1
      }

      // MARK: - UIGestureRecognizerDelegate

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === tapRecognizer || gestureRecognizer === longPressRecognizer {
          return true
        }

        guard gestureRecognizer === panRecognizer else { return true }
        guard !isAnimating else { return false }

        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y) + 12
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        true
      }

      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view is UIControl {
          return false
        }
        return true
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        let typeName = String(describing: type(of: otherGestureRecognizer))
        return typeName.contains("Parallax")
          || typeName.contains("ZoomTransition")
          || typeName.contains("ScreenEdgePan")
          || typeName.contains("FullPageSwipe")
          || typeName == "_UIContentSwipeDismissGestureRecognizer"
      }
    }
  }

  @MainActor
  final class CoverEpubContainerViewController: UIViewController {
    weak var coordinator: WebPubPagedCoverView.Coordinator?

    override func viewDidLoad() {
      super.viewDidLoad()
      view.clipsToBounds = true
      coordinator?.setupGestures(on: view)
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      guard let coordinator, !coordinator.isAnimating else { return }
      guard coordinator.currentController != nil else { return }
      coordinator.handleContainerLayout()
    }
  }
#endif
