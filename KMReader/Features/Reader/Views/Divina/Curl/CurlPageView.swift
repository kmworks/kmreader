//
// CurlPageView.swift
//

#if os(iOS)
  import Foundation
  import SwiftUI
  import UIKit

  struct CurlPageView: UIViewControllerRepresentable {
    @Bindable var viewModel: ReaderViewModel
    let mode: PageViewMode
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let animateTapTurns: Bool
    let renderConfig: ReaderRenderConfig
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
      let spineLocation: UIPageViewController.SpineLocation = mode.isRTL ? .max : .min
      let pageViewController = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: mode.isVertical ? .vertical : .horizontal,
        options: [.spineLocation: NSNumber(value: spineLocation.rawValue)]
      )

      context.coordinator.attach(to: pageViewController)
      context.coordinator.installTapRecognizers(on: pageViewController.view)

      for recognizer in pageViewController.gestureRecognizers {
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
        pageViewController: pageViewController,
        semanticContentAttribute: mode.isRTL ? .forceRightToLeft : .forceLeftToRight
      )
      PageCurlBacksideViewController.applyStyle(pageCurlBacksideStyle(), to: pageViewController)
      context.coordinator.installInitialControllers(on: pageViewController)

      return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
      context.coordinator.update(parent: self, pageViewController: pageViewController)
    }

    static func dismantleUIViewController(
      _ pageViewController: UIPageViewController,
      coordinator: Coordinator
    ) {
      coordinator.teardown(from: pageViewController)
    }

    func pageCurlBacksideStyle() -> PageCurlBacksideViewController.Style {
      PageCurlBacksideViewController.Style(
        baseColor: UIColor(renderConfig.readerBackground.color)
      )
    }

    func pageCurlBacksideMirrorAxis() -> PageCurlBacksideViewController.MirrorAxis {
      mode.isVertical ? .vertical : .horizontal
    }
  }
#endif
