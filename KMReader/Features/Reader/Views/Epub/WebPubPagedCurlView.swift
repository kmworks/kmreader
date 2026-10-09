//
// WebPubPagedCurlView.swift
//
//

#if os(iOS)
  import SwiftUI
  import UIKit
  import WebKit

  struct WebPubPagedCurlView: UIViewControllerRepresentable {
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

    func makeUIViewController(context: Context) -> UIPageViewController {
      let spineLocation = pageCurlSpineLocation
      let options: [UIPageViewController.OptionsKey: Any] = [.spineLocation: NSNumber(value: spineLocation.rawValue)]

      let pageVC = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: .horizontal,
        options: options
      )
      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: pageCurlSemanticContentAttribute
      )
      pageVC.dataSource = context.coordinator
      pageVC.delegate = context.coordinator
      PageCurlBacksideViewController.applyStyle(pageCurlBacksideStyle(), to: pageVC)
      context.coordinator.pageViewController = pageVC

      // Allow simultaneous gesture recognition for zoom transition return gesture
      pageVC.gestureRecognizers.forEach { recognizer in
        recognizer.delegate = context.coordinator
        if recognizer is UITapGestureRecognizer {
          recognizer.isEnabled = false
        }
        if let pan = recognizer as? UIPanGestureRecognizer {
          pan.addTarget(context.coordinator, action: #selector(Coordinator.handleInternalPanState(_:)))
        }
      }

      // Custom tap/long-press handling with TapZoneHelper
      let tapRecognizer = UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleTap(_:))
      )
      tapRecognizer.cancelsTouchesInView = false
      tapRecognizer.delegate = context.coordinator
      pageVC.view.addGestureRecognizer(tapRecognizer)
      context.coordinator.tapGestureRecognizer = tapRecognizer

      let longPressRecognizer = UILongPressGestureRecognizer(
        target: context.coordinator,
        action: #selector(Coordinator.handleLongPress(_:))
      )
      longPressRecognizer.cancelsTouchesInView = false
      longPressRecognizer.delegate = context.coordinator
      tapRecognizer.require(toFail: longPressRecognizer)
      pageVC.view.addGestureRecognizer(longPressRecognizer)
      context.coordinator.longPressGestureRecognizer = longPressRecognizer

      context.coordinator.installInitialLocation(in: pageVC)

      return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
      context.coordinator.parent = self
      defer { context.coordinator.hasCompletedInitialUpdate = true }
      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: pageCurlSemanticContentAttribute
      )
      PageCurlBacksideViewController.applyStyle(pageCurlBacksideStyle(), to: pageVC)

      if context.coordinator.currentChapterController == nil {
        context.coordinator.installInitialLocation(in: pageVC)
      }

      if let targetChapterIndex = viewModel.targetChapterIndex,
        let targetPageIndex = viewModel.targetPageIndex,
        !context.coordinator.hasActiveTurnSession,
        !context.coordinator.isAnimating,
        !(pageVC.transitionCoordinator?.isAnimated ?? false),
        targetChapterIndex >= 0,
        targetChapterIndex < viewModel.chapterCount,
        targetChapterIndex != context.coordinator.currentChapterIndex
          || targetPageIndex != context.coordinator.currentPageIndex
      {
        context.coordinator.performProgrammaticTurn(
          chapterIndex: targetChapterIndex,
          pageIndex: targetPageIndex,
          in: pageVC
        )
      }

      context.coordinator.reconfigureHosts()
    }

    private func pageCurlBacksideStyle() -> PageCurlBacksideViewController.Style {
      PageCurlBacksideViewController.Style(
        baseColor: preferences.resolvedTheme(for: colorScheme).uiColorBackground
      )
    }

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: viewModel.publicationLanguage,
        readingProgression: viewModel.publicationReadingProgression
      )
    }

    private var pageCurlSpineLocation: UIPageViewController.SpineLocation {
      paginationLayout.reversesHorizontalGestureDirection ? .max : .min
    }

    private var pageCurlSemanticContentAttribute: UISemanticContentAttribute {
      paginationLayout.reversesHorizontalGestureDirection ? .forceRightToLeft : .forceLeftToRight
    }

    private func pageCurlNavigationDirection(forward: Bool) -> UIPageViewController.NavigationDirection {
      if paginationLayout.reversesHorizontalGestureDirection {
        return forward ? .reverse : .forward
      }
      return forward ? .forward : .reverse
    }

    private func pageCurlControllers(
      primary: UIViewController,
      backside: UIViewController,
      animated: Bool,
      in pageVC: UIPageViewController
    ) -> [UIViewController] {
      PageCurlControllerPlanner.controllers(
        primary: primary,
        animated: animated,
        in: pageVC,
        makeBackside: { backside }
      )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
      UIGestureRecognizerDelegate
    {
      var parent: WebPubPagedCurlView
      var currentChapterIndex: Int
      var currentPageIndex: Int
      var isAnimating = false
      weak var pageViewController: UIPageViewController?
      weak var tapGestureRecognizer: UITapGestureRecognizer?
      weak var longPressGestureRecognizer: UILongPressGestureRecognizer?
      var hasCompletedInitialUpdate = false

      private(set) var currentChapterController: EpubPageViewController?
      private var nextChapterController: EpubPageViewController?
      private var previousChapterController: EpubPageViewController?
      private var frontShell: CurlPageShellViewController?
      private var turnSession: TurnSession?
      var hasActiveTurnSession: Bool { turnSession != nil }

      private struct TurnTarget {
        let controller: EpubPageViewController
        let chapterIndex: Int
        let subPageIndex: Int
        let isCrossChapter: Bool
        let isForward: Bool
      }

      private struct TurnSession {
        let isInteractive: Bool
        let target: TurnTarget
        let targetShell: CurlPageShellViewController
        let leafShell: CurlPageShellViewController
        let leafSnapshot: UIView?
        let backside: PageCurlBacksideViewController
        let originPage: Int
      }

      private typealias PageTarget = (chapterIndex: Int, subPageIndex: Int, preferLastPage: Bool)

      private var paginationLayout: WebPubPaginationLayout {
        parent.paginationLayout
      }

      init(_ parent: WebPubPagedCurlView) {
        self.parent = parent
        self.currentChapterIndex = parent.viewModel.currentChapterIndex
        self.currentPageIndex = parent.viewModel.currentPageIndex
      }

      // MARK: - Installation

      func installInitialLocation(in pageVC: UIPageViewController) {
        let chapterIndex = parent.viewModel.currentChapterIndex
        let pageCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
        let pageIndex = max(0, min(parent.viewModel.currentPageIndex, pageCount - 1))
        guard chapterIndex >= 0,
          chapterIndex < parent.viewModel.chapterCount,
          let controller = makeChapterController(chapterIndex: chapterIndex, subPageIndex: pageIndex)
        else {
          PageCurlControllerPlanner.safeSetViewControllers(
            PageCurlControllerPlanner.placeholderControllers(
              in: pageVC,
              backgroundColor: parent.preferences.resolvedTheme(for: parent.colorScheme).uiColorBackground
            ),
            on: pageVC,
            direction: .forward,
            animated: false
          )
          return
        }
        installCurrent(controller, in: pageVC)
        commitLocation(chapterIndex: chapterIndex, pageIndex: pageIndex, notify: false)
      }

      private func installCurrent(_ controller: EpubPageViewController, in pageVC: UIPageViewController) {
        currentChapterController = controller
        controller.loadViewIfNeeded()
        controller.forceEnsureContentLoaded()
        let shell = CurlPageShellViewController()
        shell.view.frame = pageVC.view.bounds
        shell.adopt(controller)
        frontShell = shell
        PageCurlControllerPlanner.safeSetViewControllers(
          [shell],
          on: pageVC,
          direction: .forward,
          animated: false
        )
        refreshNeighbors()
      }

      // MARK: - Chapter hosts

      func makeChapterController(
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
          guard self.currentChapterController === controller, self.turnSession == nil else { return }
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
        if let currentChapterController { reconfigureHost(currentChapterController) }
        if let nextChapterController { reconfigureHost(nextChapterController) }
        if let previousChapterController { reconfigureHost(previousChapterController) }
      }

      // MARK: - Neighbor preloading

      private func nextPageTarget(
        chapterIndex: Int,
        subPageIndex: Int
      ) -> PageTarget? {
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
      ) -> PageTarget? {
        if subPageIndex > 0 {
          return (chapterIndex, subPageIndex - 1, false)
        }
        let previousChapter = chapterIndex - 1
        guard previousChapter >= 0 else { return nil }
        let previousCount = parent.viewModel.chapterPageCount(at: previousChapter) ?? 1
        return (previousChapter, max(0, previousCount - 1), previousCount <= 1)
      }

      private func refreshNeighbors(reusing detached: [EpubPageViewController] = []) {
        guard let current = currentChapterController else { return }
        let chapterIndex = current.chapterIndex
        // Coordinator position fields still hold the previous location until commitLocation runs.
        let subPageIndex = current.currentSubPageIndex

        if let nextTarget = nextPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex),
          nextTarget.chapterIndex != chapterIndex
        {
          if nextChapterController?.chapterIndex != nextTarget.chapterIndex {
            let host =
              detached.first { $0.chapterIndex == nextTarget.chapterIndex }
              ?? makeChapterController(
                chapterIndex: nextTarget.chapterIndex,
                subPageIndex: nextTarget.subPageIndex,
                preferLastPageOnReady: nextTarget.preferLastPage
              )
            if let host {
              if host.currentSubPageIndex != nextTarget.subPageIndex, !nextTarget.preferLastPage {
                host.scrollToPageIndex(nextTarget.subPageIndex)
              }
              host.loadViewIfNeeded()
              host.forceEnsureContentLoaded()
            }
            nextChapterController = host
          }
        } else {
          nextChapterController = nil
        }

        if let prevTarget = previousPageTarget(chapterIndex: chapterIndex, subPageIndex: subPageIndex),
          prevTarget.chapterIndex != chapterIndex
        {
          if previousChapterController?.chapterIndex != prevTarget.chapterIndex {
            let host =
              detached.first { $0.chapterIndex == prevTarget.chapterIndex }
              ?? makeChapterController(
                chapterIndex: prevTarget.chapterIndex,
                subPageIndex: prevTarget.subPageIndex,
                preferLastPageOnReady: prevTarget.preferLastPage
              )
            if let host {
              if host.currentSubPageIndex != prevTarget.subPageIndex, !prevTarget.preferLastPage {
                host.scrollToPageIndex(prevTarget.subPageIndex)
              }
              host.loadViewIfNeeded()
              host.forceEnsureContentLoaded()
            }
            previousChapterController = host
          }
        } else {
          previousChapterController = nil
        }
      }

      // MARK: - Turns

      private func prepareTurnTarget(
        chapterIndex: Int,
        subPageIndex: Int,
        preferLastPageOnReady: Bool,
        isForward: Bool
      ) -> TurnTarget? {
        guard let current = currentChapterController else { return nil }
        if chapterIndex == current.chapterIndex {
          return TurnTarget(
            controller: current,
            chapterIndex: chapterIndex,
            subPageIndex: subPageIndex,
            isCrossChapter: false,
            isForward: isForward
          )
        }
        let neighbor: EpubPageViewController?
        if nextChapterController?.chapterIndex == chapterIndex {
          neighbor = nextChapterController
        } else if previousChapterController?.chapterIndex == chapterIndex {
          neighbor = previousChapterController
        } else {
          neighbor = nil
        }
        guard
          let host = neighbor
            ?? makeChapterController(
              chapterIndex: chapterIndex,
              subPageIndex: subPageIndex,
              preferLastPageOnReady: preferLastPageOnReady
            )
        else { return nil }
        if host.currentSubPageIndex != subPageIndex, !preferLastPageOnReady {
          host.scrollToPageIndex(subPageIndex)
        }
        return TurnTarget(
          controller: host,
          chapterIndex: chapterIndex,
          subPageIndex: subPageIndex,
          isCrossChapter: true,
          isForward: isForward
        )
      }

      private func makeTurnSession(target: TurnTarget, originPage: Int, isInteractive: Bool) -> TurnSession? {
        guard let pageVC = pageViewController, let leaf = frontShell else { return nil }
        let targetShell = CurlPageShellViewController()
        // Pre-size so the hosted web view never passes through a zero-size layout,
        // which would trigger a throwaway re-pagination.
        targetShell.view.frame = pageVC.view.bounds

        let leafSnapshot: UIView?
        let mirror: PageCurlBacksideViewController.MirroredSnapshot?
        if target.isCrossChapter {
          target.controller.loadViewIfNeeded()
          target.controller.forceEnsureContentLoaded()
          targetShell.adopt(target.controller)
          leafSnapshot = nil
          mirror = crossChapterMirror(target: target)
        } else {
          guard let current = currentChapterController,
            let snapshot = current.view.snapshotView(afterScreenUpdates: false)
          else { return nil }
          mirror = PageCurlBacksideViewController.makeMirroredSnapshot(from: current, axis: .horizontal)
          leaf.pin(snapshot)
          targetShell.adopt(current)
          current.scrollToPageIndex(target.subPageIndex)
          leafSnapshot = snapshot
        }

        let backside = PageCurlBacksideViewController(
          destinationToken: "\(target.chapterIndex):\(target.subPageIndex)",
          style: parent.pageCurlBacksideStyle(),
          mirroredSnapshot: mirror
        )
        return TurnSession(
          isInteractive: isInteractive,
          target: target,
          targetShell: targetShell,
          leafShell: leaf,
          leafSnapshot: leafSnapshot,
          backside: backside,
          originPage: originPage
        )
      }

      private func crossChapterMirror(
        target: TurnTarget
      ) -> PageCurlBacksideViewController.MirroredSnapshot? {
        guard let current = currentChapterController else { return nil }
        if target.isForward {
          return PageCurlBacksideViewController.makeMirroredSnapshot(from: current, axis: .horizontal)
        }
        if let image = target.controller.makeBacksideSnapshotImage() {
          return PageCurlBacksideViewController.makeMirroredSnapshot(from: image, axis: .horizontal)
        }
        return PageCurlBacksideViewController.makeMirroredSnapshot(from: current, axis: .horizontal)
      }

      func performProgrammaticTurn(chapterIndex: Int, pageIndex: Int, in pageVC: UIPageViewController) {
        let pageCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
        let isLastPageRequest = pageIndex < 0
        let normalizedPageIndex =
          isLastPageRequest
          ? max(0, pageCount - 1)
          : max(0, min(pageIndex, pageCount - 1))
        let isForward =
          chapterIndex > currentChapterIndex
          || (chapterIndex == currentChapterIndex && normalizedPageIndex > currentPageIndex)

        guard
          let target = prepareTurnTarget(
            chapterIndex: chapterIndex,
            subPageIndex: normalizedPageIndex,
            preferLastPageOnReady: isLastPageRequest,
            isForward: isForward
          )
        else { return }

        let shouldAnimate = hasCompletedInitialUpdate && parent.animateTapTurns
        if shouldAnimate,
          let session = makeTurnSession(target: target, originPage: currentPageIndex, isInteractive: false)
        {
          isAnimating = true
          turnSession = session
          let controllers = parent.pageCurlControllers(
            primary: session.targetShell,
            backside: session.backside,
            animated: true,
            in: pageVC
          )
          PageCurlControllerPlanner.safeSetViewControllers(
            controllers,
            on: pageVC,
            direction: parent.pageCurlNavigationDirection(forward: isForward),
            animated: true
          ) { [weak self] completed in
            guard let self, let session = self.turnSession else { return }
            self.isAnimating = false
            if completed {
              self.commitTurnSession(session, in: pageVC)
            } else {
              self.cancelTurnSession(session)
            }
          }
        } else {
          installTurnTarget(target, in: pageVC)
          commitLocation(
            chapterIndex: target.chapterIndex,
            pageIndex: target.subPageIndex,
            notify: true
          )
        }
      }

      private func installTurnTarget(_ target: TurnTarget, in pageVC: UIPageViewController) {
        if target.isCrossChapter {
          let detached = [currentChapterController, nextChapterController, previousChapterController]
            .compactMap { $0 }
            .filter { $0 !== target.controller }
          currentChapterController = target.controller
          nextChapterController = nil
          previousChapterController = nil
          target.controller.loadViewIfNeeded()
          target.controller.forceEnsureContentLoaded()
          let shell = CurlPageShellViewController()
          shell.view.frame = pageVC.view.bounds
          shell.adopt(target.controller)
          frontShell = shell
          PageCurlControllerPlanner.safeSetViewControllers(
            [shell],
            on: pageVC,
            direction: .forward,
            animated: false
          )
          refreshNeighbors(reusing: detached)
        } else {
          target.controller.scrollToPageIndex(target.subPageIndex)
          refreshNeighbors()
        }
      }

      private func commitTurnSession(_ session: TurnSession, in pageVC: UIPageViewController) {
        turnSession = nil
        if pageVC.viewControllers?.first !== session.targetShell {
          PageCurlControllerPlanner.safeSetViewControllers(
            [session.targetShell],
            on: pageVC,
            direction: .forward,
            animated: false
          )
        }
        frontShell = session.targetShell
        if session.target.isCrossChapter {
          let detached = [currentChapterController, nextChapterController, previousChapterController]
            .compactMap { $0 }
            .filter { $0 !== session.target.controller }
          currentChapterController = session.target.controller
          nextChapterController = nil
          previousChapterController = nil
          refreshNeighbors(reusing: detached)
        } else {
          refreshNeighbors()
        }
        commitLocation(
          chapterIndex: session.target.chapterIndex,
          pageIndex: session.target.subPageIndex,
          notify: true
        )
      }

      private func cancelTurnSession(_ session: TurnSession) {
        turnSession = nil
        guard !session.target.isCrossChapter else { return }
        guard let current = currentChapterController else {
          session.leafSnapshot?.removeFromSuperview()
          return
        }
        session.leafShell.adopt(current)
        // Keep the leaf snapshot on top until the live view has scrolled back to it.
        current.scrollToPageIndex(session.originPage) {
          session.leafSnapshot?.removeFromSuperview()
        }
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

      // MARK: - UIPageViewControllerDataSource

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
      ) -> UIViewController? {
        dataSourceSibling(after: false, of: viewController, in: pageViewController)
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
      ) -> UIViewController? {
        dataSourceSibling(after: true, of: viewController, in: pageViewController)
      }

      private func dataSourceSibling(
        after: Bool,
        of viewController: UIViewController,
        in pageVC: UIPageViewController
      ) -> UIViewController? {
        if viewController is PageCurlBacksideViewController {
          return turnSession?.targetShell
        }
        guard viewController === frontShell,
          turnSession == nil,
          let current = currentChapterController
        else { return nil }

        let target =
          after
          ? pageViewControllerAfterTarget(from: current)
          : pageViewControllerBeforeTarget(from: current)
        guard let target else { return nil }

        let isForward =
          target.chapterIndex > current.chapterIndex
          || (target.chapterIndex == current.chapterIndex && target.subPageIndex > currentPageIndex)
        guard
          let turnTarget = prepareTurnTarget(
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            preferLastPageOnReady: target.preferLastPage,
            isForward: isForward
          ),
          let session = makeTurnSession(target: turnTarget, originPage: currentPageIndex, isInteractive: true)
        else { return nil }

        turnSession = session
        return session.backside
      }

      private func pageViewControllerBeforeTarget(from current: EpubPageViewController) -> PageTarget? {
        if paginationLayout.reversesHorizontalGestureDirection {
          return nextPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
        }
        return previousPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
      }

      private func pageViewControllerAfterTarget(from current: EpubPageViewController) -> PageTarget? {
        if paginationLayout.reversesHorizontalGestureDirection {
          return previousPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
        }
        return nextPageTarget(chapterIndex: current.chapterIndex, subPageIndex: currentPageIndex)
      }

      // MARK: - UIPageViewControllerDelegate

      func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
      ) {
        guard !pendingViewControllers.isEmpty else { return }
        isAnimating = true
        for controller in pendingViewControllers {
          if let backside = controller as? PageCurlBacksideViewController {
            backside.updateStyle(parent.pageCurlBacksideStyle())
          }
        }
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
      ) {
        guard let session = turnSession, session.isInteractive else { return }
        isAnimating = false
        if completed {
          commitTurnSession(session, in: pageViewController)
        } else {
          cancelTurnSession(session)
        }
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
      ) -> UIPageViewController.SpineLocation {
        parent.pageCurlSpineLocation
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
        guard let current = currentChapterController else { return false }
        let lastChapterIndex = parent.viewModel.chapterCount - 1
        guard current.chapterIndex == lastChapterIndex else { return false }
        let storedCount = parent.viewModel.chapterPageCount(at: lastChapterIndex) ?? 1
        let pageCount = max(storedCount, current.totalPagesInChapter)
        return currentPageIndex >= pageCount - 1
      }

      // MARK: - UIGestureRecognizerDelegate

      @objc func handleInternalPanState(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .ended, .cancelled, .failed:
          // A dataSource prefetch that never became a curl leaves a session behind.
          if !isAnimating, let session = turnSession, session.isInteractive {
            cancelTurnSession(session)
          }
        default:
          break
        }
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pageVC = pageViewController,
          let current = currentChapterController
        else {
          return true
        }

        if gestureRecognizer === tapGestureRecognizer || gestureRecognizer === longPressGestureRecognizer {
          return true
        }

        // Check if this is UIPageViewController's internal gesture
        guard gestureRecognizer.view === pageVC.view || gestureRecognizer.view?.superview === pageVC.view else {
          return true
        }

        let isAtFirstPage = current.chapterIndex == 0 && currentPageIndex <= 0
        let lastChapterIndex = parent.viewModel.chapterCount - 1
        let atLastPage: Bool = {
          if current.chapterIndex == lastChapterIndex {
            let storedCount = parent.viewModel.chapterPageCount(at: lastChapterIndex) ?? 1
            let pageCount = max(storedCount, current.totalPagesInChapter)
            return currentPageIndex >= pageCount - 1
          }
          return false
        }()

        // For tap gestures, check tap location
        if let tapGesture = gestureRecognizer as? UITapGestureRecognizer {
          let location = tapGesture.location(in: pageVC.view)
          let viewWidth = pageVC.view.bounds.width
          let tapZoneWidth = viewWidth * 0.3

          let isPreviousTap =
            paginationLayout.reversesHorizontalGestureDirection
            ? location.x > viewWidth - tapZoneWidth
            : location.x < tapZoneWidth
          let isNextTap =
            paginationLayout.reversesHorizontalGestureDirection
            ? location.x < tapZoneWidth
            : location.x > viewWidth - tapZoneWidth

          if isAtFirstPage && isPreviousTap {
            return false
          }

          if atLastPage && isNextTap {
            parent.onEndReached()
            return false
          }
        } else if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
          let translation = panGesture.translation(in: pageVC.view)
          let velocity = panGesture.velocity(in: pageVC.view)
          let directionSignal = horizontalGestureDirectionSignal(
            translationX: translation.x,
            velocityX: velocity.x
          )

          if directionSignal == 0 {
            return !isAtFirstPage && !atLastPage
          }

          if horizontalGestureSignalIsForward(directionSignal) {
            if atLastPage {
              parent.onEndReached()
              return false
            }
          } else if isAtFirstPage {
            return false
          }
        }

        return true
      }

      private func horizontalGestureDirectionSignal(
        translationX: CGFloat,
        velocityX: CGFloat
      ) -> CGFloat {
        if abs(translationX) >= 1 {
          return translationX
        }
        if abs(velocityX) >= 60 {
          return velocityX
        }
        return 0
      }

      private func horizontalGestureSignalIsForward(_ signal: CGFloat) -> Bool {
        paginationLayout.reversesHorizontalGestureDirection ? signal > 0 : signal < 0
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
    }
  }

  @MainActor
  final class CurlPageShellViewController: UIViewController {
    // Appearance forwarding would re-run pagination in the hosted web view on every
    // turn; containment alone is enough for safe-area propagation.
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    override func loadView() {
      let contentView = UIView()
      contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view = contentView
    }

    func pin(_ content: UIView) {
      content.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(content)
      NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: view.topAnchor),
        content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    }

    func adopt(_ child: UIViewController) {
      if child.parent !== self {
        if child.parent != nil {
          child.willMove(toParent: nil)
          child.view.removeFromSuperview()
          child.removeFromParent()
        }
        addChild(child)
        child.didMove(toParent: self)
      }
      if child.view.superview !== view {
        pin(child.view)
      }
    }
  }

  @MainActor
  final class EpubPageViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    var chapterIndex: Int
    var currentSubPageIndex: Int
    var totalPagesInChapter: Int
    private var containerInsets: UIEdgeInsets
    private var theme: ReaderTheme
    private var contentCSS: String
    private var readiumProperties: [String: String?]
    private var publicationLanguage: String?
    private var publicationReadingProgression: WebPubReadingProgression?
    private var chapterURL: URL?
    private var chapterMediaType: String?
    private var rootURL: URL?
    private var mediaTypesByRelativePath: [String: String]
    private var lastLayoutSize: CGSize = .zero
    private var isContentLoaded = false
    private var pendingPageIndex: Int?
    private var onPageCountReady: ((Int) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    var onPageIndexAdjusted: ((Int) -> Void)?
    var preferLastPageOnReady = false
    var targetProgressionOnReady: Double?

    private var bookTitle: String?
    private var chapterTitle: String?
    private var totalProgression: Double?
    private var overlayPreferences: EpubOverlayPreferences
    private var showingControls: Bool = false
    private var labelTopOffset: CGFloat
    private var labelBottomOffset: CGFloat
    private var useSafeArea: Bool

    private var paginationLayout: WebPubPaginationLayout {
      WebPubPaginationLayout.resolve(
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
      )
    }

    private let epubResourceSchemeHandler = EpubResourceSchemeHandler()

    private var infoOverlay: WebPubInfoOverlaySupport.UIKitOverlay?

    private var loadingIndicator: UIActivityIndicatorView?

    init(
      chapterURL: URL?,
      chapterMediaType: String?,
      rootURL: URL?,
      mediaTypesByRelativePath: [String: String],
      containerInsets: UIEdgeInsets,
      theme: ReaderTheme,
      contentCSS: String,
      readiumProperties: [String: String?],
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      chapterIndex: Int,
      subPageIndex: Int,
      totalPages: Int,
      bookTitle: String?,
      chapterTitle: String?,
      totalProgression: Double?,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      labelTopOffset: CGFloat,
      labelBottomOffset: CGFloat,
      useSafeArea: Bool,
      onPageCountReady: ((Int) -> Void)?
    ) {
      self.chapterURL = chapterURL
      self.chapterMediaType = chapterMediaType
      self.rootURL = rootURL
      self.mediaTypesByRelativePath = mediaTypesByRelativePath
      self.containerInsets = containerInsets
      self.theme = theme
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
      self.chapterIndex = chapterIndex
      self.currentSubPageIndex = subPageIndex
      self.totalPagesInChapter = totalPages
      self.bookTitle = bookTitle
      self.chapterTitle = chapterTitle
      self.totalProgression = totalProgression
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.labelTopOffset = labelTopOffset
      self.labelBottomOffset = labelBottomOffset
      self.useSafeArea = useSafeArea
      self.onPageCountReady = onPageCountReady
      self.onLinkTap = nil
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      setupWebView()
      setupOverlayLabels()
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAppDidBecomeActive),
        name: UIApplication.didBecomeActiveNotification,
        object: nil
      )
      loadContentIfNeeded(force: true)
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      refreshDisplay()
      updateOverlayLabels()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      // Force layout and refresh if WebView size was 0 before
      // This handles cases where UIPageViewController hasn't laid out the WebView yet
      let webViewSize = webView?.bounds.size ?? .zero
      if webViewSize.width > 0 && webViewSize.height > 0 && webViewSize != lastLayoutSize {
        lastLayoutSize = webViewSize
        refreshDisplay()
      }
    }

    @objc private func handleAppDidBecomeActive() {
      refreshDisplay()
      updateOverlayLabels()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let size = view.bounds.size
      let webViewSize = webView?.bounds.size ?? .zero
      guard size.width > 0, size.height > 0 else {
        return
      }

      // Always track WebView size changes, even if it's currently 0x0
      // This ensures we detect when WebView transitions from 0x0 to valid size
      if webViewSize != lastLayoutSize {
        lastLayoutSize = webViewSize

        // Only refresh if WebView has valid size
        if webViewSize.width > 0 && webViewSize.height > 0 {
          refreshDisplay()
          updateOverlayLabels()
        }
      }
    }

    func configure(
      chapterURL: URL?,
      chapterMediaType: String?,
      rootURL: URL?,
      mediaTypesByRelativePath: [String: String],
      containerInsets: UIEdgeInsets,
      theme: ReaderTheme,
      contentCSS: String,
      readiumProperties: [String: String?],
      publicationLanguage: String?,
      publicationReadingProgression: WebPubReadingProgression?,
      chapterIndex: Int,
      subPageIndex: Int,
      totalPages: Int,
      bookTitle: String?,
      chapterTitle: String?,
      totalProgression: Double?,
      overlayPreferences: EpubOverlayPreferences,
      showingControls: Bool,
      labelTopOffset: CGFloat,
      labelBottomOffset: CGFloat,
      useSafeArea: Bool,
      onPageCountReady: ((Int) -> Void)?
    ) {
      let shouldReload =
        chapterURL != self.chapterURL
        || chapterMediaType != self.chapterMediaType
        || rootURL != self.rootURL
        || mediaTypesByRelativePath != self.mediaTypesByRelativePath
      let appearanceChanged =
        theme != self.theme
        || containerInsets != self.containerInsets
        || contentCSS != self.contentCSS
        || readiumProperties != self.readiumProperties
        || publicationLanguage != self.publicationLanguage
        || publicationReadingProgression != self.publicationReadingProgression
        || labelTopOffset != self.labelTopOffset
        || labelBottomOffset != self.labelBottomOffset
        || useSafeArea != self.useSafeArea

      // Reset layout size when chapter changes to ensure proper size detection
      if chapterIndex != self.chapterIndex {
        lastLayoutSize = .zero
      }

      self.chapterURL = chapterURL
      self.chapterMediaType = chapterMediaType
      self.rootURL = rootURL
      self.mediaTypesByRelativePath = mediaTypesByRelativePath
      epubResourceSchemeHandler.configure(rootURL: rootURL, mediaTypesByRelativePath: mediaTypesByRelativePath)
      self.containerInsets = containerInsets
      self.theme = theme
      self.contentCSS = contentCSS
      self.readiumProperties = readiumProperties
      self.publicationLanguage = publicationLanguage
      self.publicationReadingProgression = publicationReadingProgression
      self.chapterIndex = chapterIndex
      self.currentSubPageIndex = subPageIndex
      self.totalPagesInChapter = totalPages
      self.bookTitle = bookTitle
      self.chapterTitle = chapterTitle
      self.totalProgression = totalProgression
      self.overlayPreferences = overlayPreferences
      self.showingControls = showingControls
      self.labelTopOffset = labelTopOffset
      self.labelBottomOffset = labelBottomOffset
      self.useSafeArea = useSafeArea
      self.onPageCountReady = onPageCountReady

      guard isViewLoaded else { return }

      updateOverlayLabels()

      if appearanceChanged {
        applyContainerInsets()
      }

      applyTheme()
      if shouldReload {
        loadContentIfNeeded(force: true)
      } else if appearanceChanged || preferLastPageOnReady {
        applyPagination(scrollToPage: currentSubPageIndex)
      } else {
        if isContentLoaded {
          scrollToPage(currentSubPageIndex)
        } else {
          pendingPageIndex = currentSubPageIndex
        }
      }
    }

    func refreshDisplay() {
      applyPagination(scrollToPage: currentSubPageIndex)
    }

    private var topAnchor: NSLayoutYAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor
    }
    private var bottomAnchor: NSLayoutYAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.bottomAnchor : view.bottomAnchor
    }
    private var leadingAnchor: NSLayoutXAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.leadingAnchor : view.leadingAnchor
    }
    private var trailingAnchor: NSLayoutXAxisAnchor {
      useSafeArea ? view.safeAreaLayoutGuide.trailingAnchor : view.trailingAnchor
    }

    func setupOverlayLabels() {
      infoOverlay = WebPubInfoOverlaySupport.UIKitOverlay(
        containerView: view,
        topAnchor: topAnchor,
        bottomAnchor: bottomAnchor,
        topOffset: labelTopOffset,
        bottomOffset: labelBottomOffset,
        theme: theme
      )
    }

    func updateOverlayLabels() {
      let content = WebPubInfoOverlaySupport.content(
        flowStyle: .paged,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
        totalProgression: totalProgression,
        currentPageIndex: currentSubPageIndex,
        totalPagesInChapter: totalPagesInChapter,
        showingControls: showingControls,
        isRTL: publicationReadingProgression == .rtl,
        overlayPreferences: overlayPreferences
      )
      infoOverlay?.update(content: content, animated: true)
    }

    func forceEnsureContentLoaded() {
      loadContentIfNeeded(force: true)
    }

    func makeBacksideSnapshotImage() -> UIImage? {
      guard isViewLoaded else { return nil }
      guard isContentLoaded else { return nil }
      view.layoutIfNeeded()
      let bounds = view.bounds
      guard bounds.width > 1, bounds.height > 1 else { return nil }

      let format = UIGraphicsImageRendererFormat.preferred()
      format.opaque = false
      // Half scale: the backside is mirrored and only exposed while the curl is moving.
      format.scale = (view.window?.screen.scale ?? UIScreen.main.scale) / 2
      let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
      return renderer.image { _ in
        // drawHierarchy goes through the render server, so WKWebView content is
        // captured reliably; layer.render can produce blank images offscreen.
        view.drawHierarchy(in: bounds, afterScreenUpdates: false)
      }
    }

    private var containerView: UIView?
    private var containerConstraints:
      (
        top: NSLayoutConstraint, leading: NSLayoutConstraint,
        trailing: NSLayoutConstraint, bottom: NSLayoutConstraint
      )?

    private func setupWebView() {
      let config = WKWebViewConfiguration()
      epubResourceSchemeHandler.configure(rootURL: rootURL, mediaTypesByRelativePath: mediaTypesByRelativePath)
      config.registerEpubResourceSchemeHandler(epubResourceSchemeHandler)
      config.defaultWebpagePreferences.preferredContentMode = .mobile
      let controller = WKUserContentController()
      // Use weak wrapper to avoid retain cycle (WKUserContentController retains handlers strongly)
      controller.add(WeakWKScriptMessageHandler(delegate: self), name: "readerBridge")
      config.userContentController = controller

      // Set background to fill entire view (including safe area)
      view.backgroundColor = theme.uiColorBackground

      let container = UIView()
      container.backgroundColor = .clear
      view.addSubview(container)
      container.translatesAutoresizingMaskIntoConstraints = false

      // Container respects safe area (or view edges based on policy), with additional label spacing
      let top = container.topAnchor.constraint(equalTo: topAnchor, constant: containerInsets.top)
      let leading = container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: containerInsets.left)
      let trailing = trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: containerInsets.right)
      let bottom = bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: containerInsets.bottom)
      containerConstraints = (top, leading, trailing, bottom)
      NSLayoutConstraint.activate([top, leading, trailing, bottom])
      containerView = container

      applyContainerInsets()

      webView = WKWebView(frame: .zero, configuration: config)
      webView.navigationDelegate = self
      webView.scrollView.isScrollEnabled = false
      webView.scrollView.bounces = false
      webView.scrollView.showsHorizontalScrollIndicator = false
      webView.scrollView.showsVerticalScrollIndicator = false
      webView.scrollView.contentInsetAdjustmentBehavior = .never
      webView.isOpaque = false
      webView.alpha = 0

      applyTheme()

      container.addSubview(webView)
      webView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        webView.topAnchor.constraint(equalTo: container.topAnchor),
        webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])

      let indicator = UIActivityIndicatorView(style: .medium)
      indicator.hidesWhenStopped = true
      indicator.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(indicator)
      NSLayoutConstraint.activate([
        indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
      self.loadingIndicator = indicator
    }

    private func applyTheme() {
      // Background fills entire view (including safe area)
      view.backgroundColor = theme.uiColorBackground
      containerView?.backgroundColor = .clear
      if webView != nil {
        webView.backgroundColor = theme.uiColorBackground
        webView.scrollView.backgroundColor = .clear
      }
      loadingIndicator?.color = theme.uiColorText

      // Update overlay label colors
      infoOverlay?.apply(theme: theme)
    }

    private func applyContainerInsets() {
      guard let containerConstraints else { return }
      containerConstraints.top.constant = containerInsets.top
      containerConstraints.leading.constant = containerInsets.left
      containerConstraints.trailing.constant = containerInsets.right
      containerConstraints.bottom.constant = containerInsets.bottom
      view.layoutIfNeeded()
    }

    private func loadContentIfNeeded(force: Bool) {
      guard let chapterURL, let rootURL else { return }
      let currentURL = webView.url?.standardizedFileURL
      let urlMatches = currentURL == chapterURL.standardizedFileURL

      // If URL matches and content is loaded, just update pagination.
      // We don't hide the webview or show the loader here to avoid flickering
      // when just transitioning within the same chapter.
      if urlMatches && isContentLoaded {
        applyPagination(scrollToPage: currentSubPageIndex)
        return
      }

      // Skip reload if URL matches and not forcing
      if !force && urlMatches {
        return
      }

      // New content loading - show indicator and keep webview active but hidden
      isContentLoaded = false
      pendingPageIndex = currentSubPageIndex

      // Use a near-zero alpha instead of exactly 0.
      // WebKit sometimes throttles layout/JS execution for elements with alpha=0.
      webView.alpha = 0.01

      // Only show loading indicator if WebView has valid size (is visible)
      // For pre-loaded pages with 0x0 size, don't show indicator
      let webViewSize = webView.bounds.size
      if webViewSize.width > 0 && webViewSize.height > 0 {
        loadingIndicator?.startAnimating()
      }

      webView.loadEPUBDocument(url: chapterURL, rootURL: rootURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      isContentLoaded = true
      applyPagination(scrollToPage: pendingPageIndex ?? currentSubPageIndex)
      pendingPageIndex = nil
      // Visibility is handled in userContentController when pagination is ready
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      preferences: WKWebpagePreferences,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
      preferences.preferredContentMode = .mobile

      // Allow initial page load
      guard let url = navigationAction.request.url else {
        decisionHandler(.allow, preferences)
        return
      }

      // Allow file:// URLs for the same domain (CSS, images, etc.)
      if navigationAction.navigationType == .other {
        decisionHandler(.allow, preferences)
        return
      }

      // Handle link clicks
      if navigationAction.navigationType == .linkActivated {
        // Check if this is an internal link (same book navigation)
        if url.scheme == "file" {
          onLinkTap?(url)
          decisionHandler(.cancel, preferences)
          return
        }
        // For external links, could open in Safari later
        decisionHandler(.cancel, preferences)
        return
      }

      decisionHandler(.allow, preferences)
    }

    private func applyPagination(scrollToPage pageIndex: Int) {
      guard isViewLoaded else { return }
      guard isContentLoaded else { return }
      let size = webView.bounds.size
      guard size.width > 0, size.height > 0 else { return }

      // Use a near-zero alpha to indicate transition if not already showing.
      // This prevents WebKit from throttling layout while keeping the view hidden from users.
      if webView.alpha < 0.1 {
        webView.alpha = 0.01
        loadingIndicator?.startAnimating()
      }

      injectCSS(
        contentCSS,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: EpubThemePreferences.readiumPropertyKeys,
        language: publicationLanguage,
        readingProgression: publicationReadingProgression
      ) { [weak self] in
        self?.injectPaginationJS(targetPageIndex: pageIndex, preferLastPage: self?.preferLastPageOnReady ?? false)
      }
    }

    private func injectCSS(
      _ css: String,
      readiumProperties: [String: String?],
      readiumPropertyKeys: [String],
      language: String?,
      readingProgression: WebPubReadingProgression?,
      completion: (() -> Void)? = nil
    ) {
      let js = WebPubPagedJavaScriptBuilder.makeInjectCSSScript(
        contentCSS: css,
        readiumProperties: readiumProperties,
        readiumPropertyKeys: readiumPropertyKeys,
        language: language,
        readingProgression: readingProgression
      )
      webView.evaluateJavaScript(js) { _, _ in
        completion?()
      }
    }

    private var paginationGeneration = 0

    private func injectPaginationJS(targetPageIndex: Int, preferLastPage: Bool) {
      paginationGeneration += 1
      let js = WebPubPagedJavaScriptBuilder.makePaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        waitForLoadEvents: true,
        paginationLayout: paginationLayout,
        generation: paginationGeneration
      )
      webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func scrollToPage(_ pageIndex: Int, completion: (() -> Void)? = nil) {
      guard isContentLoaded else {
        completion?()
        return
      }
      let js = WebPubPagedJavaScriptBuilder.makeScrollToPageScript(
        pageIndex: pageIndex,
        animated: false,
        paginationLayout: paginationLayout
      )
      webView.evaluateJavaScript(js) { _, _ in completion?() }
    }

    func scrollToPageIndex(_ pageIndex: Int, completion: (() -> Void)? = nil) {
      currentSubPageIndex = pageIndex
      if isContentLoaded {
        scrollToPage(pageIndex, completion: completion)
      } else {
        pendingPageIndex = pageIndex
        completion?()
      }
      updateOverlayLabels()
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard let body = message.body as? [String: Any] else { return }
      guard let type = body["type"] as? String else { return }

      if type == "ready" {
        // A superseded pagination pass must not resurrect stale counts or positions.
        if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
        if let total = body["totalPages"] as? Int {
          let normalizedTotal = max(1, total)
          var actualPage = body["currentPage"] as? Int ?? currentSubPageIndex

          totalPagesInChapter = normalizedTotal
          onPageCountReady?(normalizedTotal)

          // Handle target progression jump if requested (e.g. on initial book open).
          // We ignore this if preferLastPageOnReady is true, as that takes precedence.
          if let progression = targetProgressionOnReady, !preferLastPageOnReady {
            let targetIndex = max(0, min(normalizedTotal - 1, Int(floor(Double(normalizedTotal) * progression))))
            if targetIndex != actualPage {
              actualPage = targetIndex
              scrollToPage(targetIndex)
            }
            targetProgressionOnReady = nil
          }

          // Sync the current sub-page index with the actual page landed on by JS or progression calculation.
          if currentSubPageIndex != actualPage {
            currentSubPageIndex = actualPage
            onPageIndexAdjusted?(actualPage)
          }

          preferLastPageOnReady = false
          updateOverlayLabels()
        }

        // Stop the loading indicator and finally show the WebView content.
        loadingIndicator?.stopAnimating()
        webView.alpha = 1
      } else if type == "pageCountUpdate", let total = body["totalPages"] as? Int {
        // Handle incremental layout updates from ResizeObserver
        if let generation = body["generation"] as? Int, generation != paginationGeneration { return }
        let normalizedTotal = max(1, total)
        if totalPagesInChapter != normalizedTotal {
          totalPagesInChapter = normalizedTotal
          onPageCountReady?(normalizedTotal)
          updateOverlayLabels()
        }
      }
    }
  }
#endif
