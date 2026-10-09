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

      let initialChapterIndex = viewModel.currentChapterIndex
      let initialPageCount = viewModel.chapterPageCount(at: initialChapterIndex) ?? 1
      let initialPageIndex = max(0, min(viewModel.currentPageIndex, initialPageCount - 1))
      if initialChapterIndex >= 0,
        initialChapterIndex < viewModel.chapterCount,
        let initialVC = context.coordinator.pageViewController(
          chapterIndex: initialChapterIndex,
          subPageIndex: initialPageIndex,
          in: pageVC
        )
      {
        let controllers = pageCurlControllers(
          primary: initialVC,
          targetChapterIndex: initialChapterIndex,
          targetSubPageIndex: initialPageIndex,
          animated: false,
          in: pageVC
        )
        PageCurlControllerPlanner.safeSetViewControllers(
          controllers,
          on: pageVC,
          direction: .forward,
          animated: false
        )
        context.coordinator.commitInstalledLocation(
          chapterIndex: initialChapterIndex,
          pageIndex: initialPageIndex
        )
        if let initialVC = initialVC as? EpubPageViewController {
          context.coordinator.preloadAdjacentPages(for: initialVC, in: pageVC)
          context.coordinator.storeBacksideSnapshotIfReady(from: initialVC)
        }
      } else {
        PageCurlControllerPlanner.safeSetViewControllers(
          PageCurlControllerPlanner.placeholderControllers(
            in: pageVC,
            backgroundColor: preferences.resolvedTheme(for: colorScheme).uiColorBackground
          ),
          on: pageVC,
          direction: .forward,
          animated: false
        )
      }

      return pageVC
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
      context.coordinator.parent = self
      defer { context.coordinator.hasCompletedInitialUpdate = true }
      PageCurlControllerPlanner.configure(
        pageViewController: uiViewController,
        semanticContentAttribute: pageCurlSemanticContentAttribute
      )
      PageCurlBacksideViewController.applyStyle(pageCurlBacksideStyle(), to: uiViewController)

      let initialChapterIndex = viewModel.currentChapterIndex
      let initialPageCount = viewModel.chapterPageCount(at: initialChapterIndex) ?? 1
      let initialPageIndex = max(0, min(viewModel.currentPageIndex, initialPageCount - 1))

      let visibleController = uiViewController.viewControllers?.first
      let needsInitialControllers =
        !context.coordinator.isAnimating
        && !(visibleController is EpubPageViewController)
        && !(visibleController is PageCurlBacksideViewController)
      if needsInitialControllers,
        initialChapterIndex >= 0,
        initialChapterIndex < viewModel.chapterCount,
        let initialVC = context.coordinator.pageViewController(
          chapterIndex: initialChapterIndex,
          subPageIndex: initialPageIndex,
          in: uiViewController
        )
      {
        let controllers = pageCurlControllers(
          primary: initialVC,
          targetChapterIndex: initialChapterIndex,
          targetSubPageIndex: initialPageIndex,
          animated: false,
          in: uiViewController
        )
        PageCurlControllerPlanner.safeSetViewControllers(
          controllers,
          on: uiViewController,
          direction: .forward,
          animated: false
        )
        context.coordinator.commitInstalledLocation(
          chapterIndex: initialChapterIndex,
          pageIndex: initialPageIndex
        )
        if let initialVC = initialVC as? EpubPageViewController {
          context.coordinator.preloadAdjacentPages(for: initialVC, in: uiViewController)
          context.coordinator.storeBacksideSnapshotIfReady(from: initialVC)
        }
      } else if needsInitialControllers {
        PageCurlControllerPlanner.safeSetViewControllers(
          PageCurlControllerPlanner.placeholderControllers(
            in: uiViewController,
            backgroundColor: preferences.resolvedTheme(for: colorScheme).uiColorBackground
          ),
          on: uiViewController,
          direction: .forward,
          animated: false
        )
      }

      if let targetChapterIndex = viewModel.targetChapterIndex,
        let targetPageIndex = viewModel.targetPageIndex,
        !context.coordinator.isAnimating,
        !(uiViewController.transitionCoordinator?.isAnimated ?? false),
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
        guard
          let targetVC = context.coordinator.pageViewController(
            chapterIndex: targetChapterIndex,
            subPageIndex: normalizedPageIndex,
            in: uiViewController,
            preferLastPageOnReady: isLastPageRequest
          ) as? EpubPageViewController
        else { return }

        let isForward =
          targetChapterIndex > context.coordinator.currentChapterIndex
          || (targetChapterIndex == context.coordinator.currentChapterIndex
            && normalizedPageIndex > context.coordinator.currentPageIndex)
        let direction = pageCurlNavigationDirection(forward: isForward)

        context.coordinator.isAnimating = true
        let shouldAnimateTransition = context.coordinator.hasCompletedInitialUpdate && animateTapTurns
        let transitionControllers = pageCurlControllers(
          primary: targetVC,
          targetChapterIndex: targetChapterIndex,
          targetSubPageIndex: normalizedPageIndex,
          animated: shouldAnimateTransition,
          in: uiViewController
        )
        PageCurlControllerPlanner.safeSetViewControllers(
          transitionControllers,
          on: uiViewController,
          direction: direction,
          animated: shouldAnimateTransition
        ) { completed in
          context.coordinator.isAnimating = false
          if completed || !shouldAnimateTransition {
            context.coordinator.currentChapterIndex = targetChapterIndex
            context.coordinator.currentPageIndex = normalizedPageIndex
            let committedControllers = pageCurlControllers(
              primary: targetVC,
              targetChapterIndex: targetChapterIndex,
              targetSubPageIndex: normalizedPageIndex,
              animated: false,
              in: uiViewController
            )
            PageCurlControllerPlanner.safeSetViewControllers(
              committedControllers,
              on: uiViewController,
              direction: direction,
              animated: false
            )
            context.coordinator.preloadAdjacentPages(for: targetVC, in: uiViewController)
            context.coordinator.storeBacksideSnapshotIfReady(from: targetVC)
            Task { @MainActor in
              viewModel.currentChapterIndex = targetChapterIndex
              viewModel.currentPageIndex = normalizedPageIndex
              viewModel.targetChapterIndex = nil
              viewModel.targetPageIndex = nil
              viewModel.pageDidChange()
            }
          }
        }
      }

      if let currentVC = uiViewController.viewControllers?.first as? EpubPageViewController {
        let chapterIndex = currentVC.chapterIndex
        let containerInsets = viewModel.containerInsetsForLabels().uiEdgeInsets
        let theme = preferences.resolvedTheme(for: colorScheme)

        let fontPath = preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
        let readiumPayload = preferences.makeReadiumPayload(
          theme: theme,
          fontPath: fontPath,
          rootURL: viewModel.resourceRootURL,
          viewportSize: viewModel.resolvedViewportSize
        )

        guard
          let location = viewModel.pageLocation(
            chapterIndex: chapterIndex,
            pageIndex: currentVC.currentSubPageIndex
          )
        else { return }
        let chapterProgress =
          location.pageCount > 0 ? Double(location.pageIndex + 1) / Double(location.pageCount) : nil
        let totalProgression = viewModel.totalProgression(
          location: location,
          chapterProgress: chapterProgress
        )

        currentVC.configure(
          chapterURL: viewModel.chapterURL(at: chapterIndex),
          chapterMediaType: viewModel.chapterMediaType(at: chapterIndex),
          rootURL: viewModel.resourceRootURL,
          mediaTypesByRelativePath: viewModel.mediaTypesByRelativePath,
          containerInsets: containerInsets,
          theme: theme,
          contentCSS: readiumPayload.css,
          readiumProperties: readiumPayload.properties,
          publicationLanguage: viewModel.publicationLanguage,
          publicationReadingProgression: viewModel.publicationReadingProgression,
          chapterIndex: chapterIndex,
          subPageIndex: currentVC.currentSubPageIndex,
          totalPages: currentVC.totalPagesInChapter,
          bookTitle: bookTitle,
          chapterTitle: location.title,
          totalProgression: totalProgression,
          overlayPreferences: overlayPreferences,
          showingControls: showingControls,
          labelTopOffset: viewModel.labelTopOffset,
          labelBottomOffset: viewModel.labelBottomOffset,
          useSafeArea: viewModel.useSafeArea,
          onPageCountReady: { [weak viewModel] pageCount in
            Task { @MainActor in
              viewModel?.updateChapterPageCount(pageCount, for: chapterIndex)
            }
          }
        )
      }
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

    private func pageCurlBacksideToken(chapterIndex: Int, subPageIndex: Int) -> String {
      "\(chapterIndex):\(subPageIndex)"
    }

    private func pageCurlBacksideTarget(from token: String) -> (chapterIndex: Int, subPageIndex: Int)? {
      let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { return nil }
      guard let chapterIndex = Int(parts[0]), let subPageIndex = Int(parts[1]) else { return nil }
      return (chapterIndex, subPageIndex)
    }

    private func pageCurlBacksideController(
      chapterIndex: Int,
      subPageIndex: Int,
      mirroredSnapshot: PageCurlBacksideViewController.MirroredSnapshot? = nil
    ) -> PageCurlBacksideViewController {
      PageCurlBacksideViewController(
        destinationToken: pageCurlBacksideToken(chapterIndex: chapterIndex, subPageIndex: subPageIndex),
        style: pageCurlBacksideStyle(),
        mirroredSnapshot: mirroredSnapshot
      )
    }

    private func pageCurlControllers(
      primary: UIViewController,
      targetChapterIndex: Int,
      targetSubPageIndex: Int,
      animated: Bool,
      in pageVC: UIPageViewController
    ) -> [UIViewController] {
      PageCurlControllerPlanner.controllers(
        primary: primary,
        animated: animated,
        in: pageVC,
        makeBackside: {
          let mirroredSnapshot = PageCurlBacksideViewController.makeMirroredSnapshot(
            from: primary,
            axis: .horizontal
          )
          return pageCurlBacksideController(
            chapterIndex: targetChapterIndex,
            subPageIndex: targetSubPageIndex,
            mirroredSnapshot: mirroredSnapshot
          )
        }
      )
    }

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
      private let maxCachedControllers = 5  // Increased from 3 to 5 to reduce eviction during transitions
      private var cachedControllers: [String: EpubPageViewController] = [:]
      private var controllerKeys: [ObjectIdentifier: String] = [:]
      private var pendingControllers: Set<ObjectIdentifier> = []  // Track controllers in transition
      private var reservedControllers: Set<ObjectIdentifier> = []
      private var reserveCleanupTask: DispatchWorkItem?
      private let maxCachedBacksideSnapshots = 6
      private var cachedBacksideImages: [String: UIImage] = [:]
      private var cachedBacksideImageOrder: [String] = []

      init(_ parent: WebPubPagedCurlView) {
        self.parent = parent
        self.currentChapterIndex = parent.viewModel.currentChapterIndex
        self.currentPageIndex = parent.viewModel.currentPageIndex
      }

      private typealias PageTarget = (chapterIndex: Int, subPageIndex: Int)

      private var paginationLayout: WebPubPaginationLayout {
        parent.paginationLayout
      }

      private func cacheKey(chapterIndex: Int, pageIndex: Int) -> String {
        "\(chapterIndex)-\(pageIndex)"
      }

      func commitInstalledLocation(chapterIndex: Int, pageIndex: Int) {
        currentChapterIndex = chapterIndex
        currentPageIndex = pageIndex
        if parent.viewModel.currentChapterIndex != chapterIndex {
          parent.viewModel.currentChapterIndex = chapterIndex
        }
        if parent.viewModel.currentPageIndex != pageIndex {
          parent.viewModel.currentPageIndex = pageIndex
        }
        if parent.viewModel.targetChapterIndex == chapterIndex,
          parent.viewModel.targetPageIndex == pageIndex
        {
          parent.viewModel.targetChapterIndex = nil
          parent.viewModel.targetPageIndex = nil
        }
      }

      func storeBacksideSnapshotIfReady(from controller: EpubPageViewController) {
        guard let image = controller.makeBacksideSnapshotImage() else { return }
        let key = cacheKey(chapterIndex: controller.chapterIndex, pageIndex: controller.currentSubPageIndex)
        cachedBacksideImages[key] = image
        cachedBacksideImageOrder.removeAll { $0 == key }
        cachedBacksideImageOrder.append(key)

        while cachedBacksideImageOrder.count > maxCachedBacksideSnapshots {
          let removedKey = cachedBacksideImageOrder.removeFirst()
          cachedBacksideImages.removeValue(forKey: removedKey)
        }
      }

      private func cachedBacksideMirroredSnapshot(
        chapterIndex: Int,
        subPageIndex: Int
      ) -> PageCurlBacksideViewController.MirroredSnapshot? {
        let key = cacheKey(chapterIndex: chapterIndex, pageIndex: subPageIndex)
        guard let image = cachedBacksideImages[key] else { return nil }
        cachedBacksideImageOrder.removeAll { $0 == key }
        cachedBacksideImageOrder.append(key)
        return PageCurlBacksideViewController.makeMirroredSnapshot(from: image, axis: .horizontal)
      }

      private func configureController(
        _ controller: EpubPageViewController
      ) {
        controller.onPageIndexAdjusted = { [weak self, weak controller] pageIndex in
          guard let self, let controller else { return }
          guard self.pageViewController?.viewControllers?.first === controller else { return }
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

      func pageViewController(
        chapterIndex: Int,
        subPageIndex: Int,
        in pageViewController: UIPageViewController?,
        preferLastPageOnReady: Bool = false
      ) -> UIViewController? {
        guard chapterIndex >= 0, chapterIndex < parent.viewModel.chapterCount else { return nil }
        let pageCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1

        // Only validate bounds if we're not using preferLastPageOnReady
        // preferLastPageOnReady allows any subPageIndex and will adjust when content loads
        if !preferLastPageOnReady {
          guard subPageIndex >= 0, subPageIndex < pageCount else { return nil }
        } else {
          // For preferLastPageOnReady, ensure subPageIndex is at least 0
          guard subPageIndex >= 0 else { return nil }
        }

        let containerInsets = parent.viewModel.containerInsetsForLabels().uiEdgeInsets
        let theme = parent.preferences.resolvedTheme(for: parent.colorScheme)

        // Ensure the selected font is copied to the resource directory

        let fontPath = parent.preferences.fontFamily.fontName.flatMap { CustomFontStore.shared.getFontPath(for: $0) }
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

        let key = cacheKey(chapterIndex: chapterIndex, pageIndex: subPageIndex)
        if let cached = cachedControllers[key] {
          cached.configure(
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
            preferLastPageOnReady: preferLastPageOnReady,
            targetProgressionOnReady: initialProgression,
            onPageCountReady: onPageCountReady
          )
          configureController(cached)
          cached.loadViewIfNeeded()
          return cached
        }

        let protectedIDs = Set((pageViewController?.viewControllers ?? []).map { ObjectIdentifier($0) })
        let allProtectedIDs = protectedIDs.union(pendingControllers).union(reservedControllers)
        if let reusable = cachedControllers.values.first(where: {
          !allProtectedIDs.contains(ObjectIdentifier($0))
        }) {
          reusable.configure(
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
            preferLastPageOnReady: preferLastPageOnReady,
            targetProgressionOnReady: initialProgression,
            onPageCountReady: onPageCountReady
          )
          configureController(reusable)
          reusable.onLinkTap = { [weak self] url in
            self?.parent.viewModel.navigateToURL(url)
          }
          reusable.loadViewIfNeeded()
          storeController(reusable, for: key)
          return reusable
        }

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
        configureController(controller)
        controller.onLinkTap = { [weak self] url in
          self?.parent.viewModel.navigateToURL(url)
        }
        controller.loadViewIfNeeded()
        storeController(controller, for: key)
        return controller
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
      ) -> UIViewController? {
        if let backsideController = viewController as? PageCurlBacksideViewController {
          guard
            let target = parent.pageCurlBacksideTarget(from: backsideController.destinationToken)
          else { return nil }
          let controller = self.pageViewController(
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            in: pageViewController
          )
          return reserveController(controller)
        }

        guard let current = viewController as? EpubPageViewController else { return nil }
        let target = pageViewControllerBeforeTarget(from: current)

        guard let target else { return nil }
        let mirroredSnapshot = mirroredSnapshotForBackside(
          from: current,
          targetChapterIndex: target.chapterIndex,
          targetSubPageIndex: target.subPageIndex,
          in: pageViewController
        )
        return reserveController(
          parent.pageCurlBacksideController(
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            mirroredSnapshot: mirroredSnapshot
          )
        )
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
      ) -> UIViewController? {
        if let backsideController = viewController as? PageCurlBacksideViewController {
          guard
            let target = parent.pageCurlBacksideTarget(from: backsideController.destinationToken)
          else { return nil }
          let controller = self.pageViewController(
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            in: pageViewController
          )
          return reserveController(controller)
        }

        guard let current = viewController as? EpubPageViewController else { return nil }
        let target = pageViewControllerAfterTarget(from: current)

        guard let target else { return nil }
        let mirroredSnapshot = mirroredSnapshotForBackside(
          from: current,
          targetChapterIndex: target.chapterIndex,
          targetSubPageIndex: target.subPageIndex,
          in: pageViewController
        )
        return reserveController(
          parent.pageCurlBacksideController(
            chapterIndex: target.chapterIndex,
            subPageIndex: target.subPageIndex,
            mirroredSnapshot: mirroredSnapshot
          )
        )
      }

      private func pageViewControllerBeforeTarget(from current: EpubPageViewController) -> PageTarget? {
        if paginationLayout.reversesHorizontalGestureDirection {
          return nextLogicalTarget(from: current)
        }
        return previousLogicalTarget(from: current)
      }

      private func pageViewControllerAfterTarget(from current: EpubPageViewController) -> PageTarget? {
        if paginationLayout.reversesHorizontalGestureDirection {
          return previousLogicalTarget(from: current)
        }
        return nextLogicalTarget(from: current)
      }

      private func previousLogicalTarget(from current: EpubPageViewController) -> PageTarget? {
        if current.chapterIndex == 0 && current.currentSubPageIndex <= 0 {
          return nil
        }
        if current.currentSubPageIndex > 0 {
          return (current.chapterIndex, current.currentSubPageIndex - 1)
        }
        let previousChapter = current.chapterIndex - 1
        guard previousChapter >= 0 else { return nil }
        let previousCount = parent.viewModel.chapterPageCount(at: previousChapter) ?? 1
        return (previousChapter, max(0, previousCount - 1))
      }

      private func nextLogicalTarget(from current: EpubPageViewController) -> PageTarget? {
        let storedCount = parent.viewModel.chapterPageCount(at: current.chapterIndex) ?? 1
        let chapterPageCount = max(storedCount, current.totalPagesInChapter)
        if current.currentSubPageIndex < chapterPageCount - 1 {
          return (current.chapterIndex, current.currentSubPageIndex + 1)
        }
        let nextChapter = current.chapterIndex + 1
        if nextChapter < parent.viewModel.chapterCount {
          return (nextChapter, 0)
        }
        return nil
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
      ) {
        guard !pendingViewControllers.isEmpty else { return }
        isAnimating = true
        clearReservedControllers()

        for controller in pendingViewControllers {
          pendingControllers.insert(ObjectIdentifier(controller))
          if let pending = controller as? EpubPageViewController {
            pending.loadViewIfNeeded()
            pending.forceEnsureContentLoaded()
          } else if let backside = controller as? PageCurlBacksideViewController {
            backside.updateStyle(parent.pageCurlBacksideStyle())
          }
        }
      }

      private func commitCurrentController(
        _ currentVC: EpubPageViewController,
        in pageViewController: UIPageViewController
      ) {
        let chapterIndex = currentVC.chapterIndex
        let storedCount = parent.viewModel.chapterPageCount(at: chapterIndex) ?? 1
        let effectiveCount = max(storedCount, currentVC.totalPagesInChapter)
        let normalizedPageIndex = max(0, min(currentVC.currentSubPageIndex, effectiveCount - 1))
        if effectiveCount != storedCount {
          parent.viewModel.updateChapterPageCount(effectiveCount, for: chapterIndex)
        }
        currentChapterIndex = chapterIndex
        currentPageIndex = normalizedPageIndex
        storeBacksideSnapshotIfReady(from: currentVC)
        preloadAdjacentPages(for: currentVC, in: pageViewController)
        Task { @MainActor in
          parent.viewModel.currentChapterIndex = chapterIndex
          parent.viewModel.currentPageIndex = normalizedPageIndex
          parent.viewModel.pageDidChange()
        }
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
      ) {
        isAnimating = false
        pendingControllers.removeAll()
        clearReservedControllers()

        guard completed,
          let visibleController = pageViewController.viewControllers?.first
        else { return }

        if let backsideController = visibleController as? PageCurlBacksideViewController {
          guard
            let target = parent.pageCurlBacksideTarget(from: backsideController.destinationToken),
            let targetController = self.pageViewController(
              chapterIndex: target.chapterIndex,
              subPageIndex: target.subPageIndex,
              in: pageViewController
            ) as? EpubPageViewController
          else { return }

          let committedControllers = parent.pageCurlControllers(
            primary: targetController,
            targetChapterIndex: target.chapterIndex,
            targetSubPageIndex: target.subPageIndex,
            animated: false,
            in: pageViewController
          )
          PageCurlControllerPlanner.safeSetViewControllers(
            committedControllers,
            on: pageViewController,
            direction: .forward,
            animated: false
          )
          commitCurrentController(targetController, in: pageViewController)
          return
        }

        guard let currentVC = visibleController as? EpubPageViewController else { return }
        commitCurrentController(currentVC, in: pageViewController)
      }

      func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
      ) -> UIPageViewController.SpineLocation {
        parent.pageCurlSpineLocation
      }

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

      private func reserveController(_ controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        reservedControllers.insert(ObjectIdentifier(controller))
        scheduleReservedControllerCleanup()
        return controller
      }

      private func scheduleReservedControllerCleanup() {
        reserveCleanupTask?.cancel()
        let cleanupTask = DispatchWorkItem { [weak self] in
          self?.reservedControllers.removeAll()
          self?.reserveCleanupTask = nil
        }
        reserveCleanupTask = cleanupTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: cleanupTask)
      }

      private func clearReservedControllers() {
        reserveCleanupTask?.cancel()
        reserveCleanupTask = nil
        reservedControllers.removeAll()
      }

      private func isForwardNavigation(
        from currentChapterIndex: Int,
        currentSubPageIndex: Int,
        to targetChapterIndex: Int,
        targetSubPageIndex: Int
      ) -> Bool {
        if targetChapterIndex != currentChapterIndex {
          return targetChapterIndex > currentChapterIndex
        }
        return targetSubPageIndex > currentSubPageIndex
      }

      private func mirroredSnapshotForBackside(
        from currentController: EpubPageViewController,
        targetChapterIndex: Int,
        targetSubPageIndex: Int,
        in pageViewController: UIPageViewController
      ) -> PageCurlBacksideViewController.MirroredSnapshot? {
        let isForward = isForwardNavigation(
          from: currentController.chapterIndex,
          currentSubPageIndex: currentController.currentSubPageIndex,
          to: targetChapterIndex,
          targetSubPageIndex: targetSubPageIndex
        )

        if !isForward,
          let cachedSnapshot = cachedBacksideMirroredSnapshot(
            chapterIndex: targetChapterIndex,
            subPageIndex: targetSubPageIndex
          )
        {
          return cachedSnapshot
        }

        let sourceController: UIViewController
        if isForward {
          sourceController = currentController
        } else if let targetController = self.pageViewController(
          chapterIndex: targetChapterIndex,
          subPageIndex: targetSubPageIndex,
          in: pageViewController
        ) {
          if let epubController = targetController as? EpubPageViewController,
            let image = epubController.makeBacksideSnapshotImage()
          {
            return PageCurlBacksideViewController.makeMirroredSnapshot(from: image, axis: .horizontal)
          }
          sourceController = targetController
        } else {
          sourceController = currentController
        }

        return PageCurlBacksideViewController.makeMirroredSnapshot(
          from: sourceController,
          axis: .horizontal
        )
      }

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
        guard let pageVC = pageViewController,
          let currentVC = pageVC.viewControllers?.first as? EpubPageViewController
        else {
          return false
        }
        let lastChapterIndex = parent.viewModel.chapterCount - 1
        guard currentVC.chapterIndex == lastChapterIndex else { return false }
        let storedCount = parent.viewModel.chapterPageCount(at: lastChapterIndex) ?? 1
        let pageCount = max(storedCount, currentVC.totalPagesInChapter)
        return currentVC.currentSubPageIndex >= pageCount - 1
      }

      private func storeController(_ controller: EpubPageViewController, for key: String) {
        let identifier = ObjectIdentifier(controller)
        if let existingKey = controllerKeys[identifier] {
          cachedControllers.removeValue(forKey: existingKey)
        }
        controllerKeys[identifier] = key
        cachedControllers[key] = controller
        if cachedControllers.count > maxCachedControllers {
          evictUnusedControllers()
        }
      }

      private func evictUnusedControllers() {
        // Protect currently visible controllers
        let protectedIDs = Set((pageViewController?.viewControllers ?? []).map { ObjectIdentifier($0) })

        // Also protect pending and reserved controllers
        let allProtectedIDs = protectedIDs.union(pendingControllers).union(reservedControllers)

        for (key, controller) in cachedControllers {
          if cachedControllers.count <= maxCachedControllers {
            break
          }
          let identifier = ObjectIdentifier(controller)
          if !allProtectedIDs.contains(identifier) {
            cachedControllers.removeValue(forKey: key)
            controllerKeys.removeValue(forKey: identifier)
          }
        }
      }

      func preloadAdjacentPages(for current: EpubPageViewController, in pageVC: UIPageViewController) {
        let storedCount = parent.viewModel.chapterPageCount(at: current.chapterIndex) ?? 1
        let chapterPageCount = max(storedCount, current.totalPagesInChapter)
        let nextSubPage = current.currentSubPageIndex + 1
        let prevSubPage = current.currentSubPageIndex - 1

        if nextSubPage < chapterPageCount {
          if let controller = pageViewController(
            chapterIndex: current.chapterIndex,
            subPageIndex: nextSubPage,
            in: pageVC
          ) as? EpubPageViewController {
            controller.loadViewIfNeeded()
            controller.forceEnsureContentLoaded()
          }
        } else {
          let nextChapter = current.chapterIndex + 1
          if nextChapter < parent.viewModel.chapterCount {
            if let controller = pageViewController(
              chapterIndex: nextChapter,
              subPageIndex: 0,
              in: pageVC
            ) as? EpubPageViewController {
              controller.loadViewIfNeeded()
              controller.forceEnsureContentLoaded()
            }
          }
        }

        if prevSubPage >= 0 {
          if let controller = pageViewController(
            chapterIndex: current.chapterIndex,
            subPageIndex: prevSubPage,
            in: pageVC
          ) as? EpubPageViewController {
            controller.loadViewIfNeeded()
            controller.forceEnsureContentLoaded()
          }
        } else {
          let previousChapter = current.chapterIndex - 1
          if previousChapter >= 0 {
            let previousCount = parent.viewModel.chapterPageCount(at: previousChapter) ?? 1
            let preferLastPageOnReady = previousCount <= 1
            if let controller = pageViewController(
              chapterIndex: previousChapter,
              subPageIndex: max(0, previousCount - 1),
              in: pageVC,
              preferLastPageOnReady: preferLastPageOnReady
            ) as? EpubPageViewController {
              controller.loadViewIfNeeded()
              controller.forceEnsureContentLoaded()
            }
          }
        }
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pageVC = pageViewController,
          let currentVC = pageVC.viewControllers?.first as? EpubPageViewController
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

        // Determine if we're at a boundary
        let isAtFirstPage = currentVC.chapterIndex == 0 && currentVC.currentSubPageIndex <= 0
        let lastChapterIndex = parent.viewModel.chapterCount - 1
        let isAtLastPage: Bool = {
          if currentVC.chapterIndex == lastChapterIndex {
            let storedCount = parent.viewModel.chapterPageCount(at: lastChapterIndex) ?? 1
            let pageCount = max(storedCount, currentVC.totalPagesInChapter)
            return currentVC.currentSubPageIndex >= pageCount - 1
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

          if isAtLastPage && isNextTap {
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
            return !isAtFirstPage && !isAtLastPage
          }

          if horizontalGestureSignalIsForward(directionSignal) {
            if isAtLastPage {
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
    private var readyToken: Int = 0
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
      preferLastPageOnReady: Bool = false,
      targetProgressionOnReady: Double? = nil,
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
      self.preferLastPageOnReady = preferLastPageOnReady
      self.targetProgressionOnReady = targetProgressionOnReady
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
      readyToken += 1

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

    private func injectPaginationJS(targetPageIndex: Int, preferLastPage: Bool) {
      let js = WebPubPagedJavaScriptBuilder.makePaginationScript(
        targetPageIndex: targetPageIndex,
        preferLastPage: preferLastPage,
        waitForLoadEvents: true,
        paginationLayout: paginationLayout
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
