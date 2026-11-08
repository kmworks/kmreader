//
// CurlDualPageView.swift
//

#if os(iOS)
  import Foundation
  import SwiftUI
  import UIKit

  struct CurlDualPageView: UIViewControllerRepresentable {
    @Bindable var viewModel: ReaderViewModel
    let mode: PageViewMode
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let animateTapTurns: Bool
    let renderConfig: ReaderRenderConfig
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    enum SpreadSlot: Int {
      case first = 0
      case second = 1
    }

    enum SlotContent {
      case page(pageID: ReaderPageID, splitMode: PageSplitMode)
      case end(segmentBookId: String)
      case placeholder
    }

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
      let options: [UIPageViewController.OptionsKey: Any] = [
        .spineLocation: NSNumber(value: UIPageViewController.SpineLocation.mid.rawValue)
      ]
      let pageVC = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: .horizontal,
        options: options
      )
      context.coordinator.pageViewController = pageVC
      pageVC.dataSource = context.coordinator
      pageVC.delegate = context.coordinator
      context.coordinator.installTapRecognizers(on: pageVC.view)

      for recognizer in pageVC.gestureRecognizers {
        recognizer.delegate = context.coordinator
        if recognizer is UIPanGestureRecognizer {
          recognizer.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handlePagePanGesture(_:))
          )
        }
        if recognizer is UITapGestureRecognizer {
          recognizer.isEnabled = false
        }
      }

      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: mode.isRTL ? .forceRightToLeft : .forceLeftToRight
      )

      let initialSpreadIndex = context.coordinator.currentResolvedSpreadIndex() ?? 0

      if let initialPair = context.coordinator.pageControllerPair(for: initialSpreadIndex) {
        PageCurlControllerPlanner.safeSetViewControllers(
          initialPair,
          on: pageVC,
          direction: .forward,
          animated: false
        )
      } else {
        PageCurlControllerPlanner.safeSetViewControllers(
          PageCurlControllerPlanner.placeholderControllers(
            in: pageVC,
            backgroundColor: UIColor(renderConfig.readerBackground.color)
          ),
          on: pageVC,
          direction: .forward,
          animated: false
        )
      }

      return pageVC
    }

    static func dismantleUIViewController(
      _ pageViewController: UIPageViewController,
      coordinator: Coordinator
    ) {
      coordinator.teardown(pageViewController: pageViewController)
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
      context.coordinator.parent = self
      context.coordinator.pageViewController = pageVC
      context.coordinator.updateViewModelObservation(viewModel)
      context.coordinator.applyDoubleTapRecognizerState()
      defer { context.coordinator.hasCompletedInitialUpdate = true }

      PageCurlControllerPlanner.configure(
        pageViewController: pageVC,
        semanticContentAttribute: mode.isRTL ? .forceRightToLeft : .forceLeftToRight
      )

      context.coordinator.syncCurrentItemWithVisibleController()
      let didViewItemsChange = context.coordinator.updateViewItemsSnapshot(
        PageCurlViewItemsSnapshot(items: viewModel.viewItems),
        preferredAnchor: viewModel.captureCurrentPositionAnchor()
      )
      guard !context.coordinator.isTransitioning, !context.coordinator.isPanGestureActive else { return }
      context.coordinator.refreshVisibleControllerConfiguration()
      context.coordinator.processNavigationTarget(
        on: pageVC,
        restoreModelPosition: didViewItemsChange
      )
    }
  }
#endif
