//
// PageCurlControllerPlanner.swift
//

#if os(iOS)
  import UIKit

  enum PageCurlControllerPlanner {
    static func configure(
      pageViewController: UIPageViewController,
      semanticContentAttribute: UISemanticContentAttribute? = nil
    ) {
      pageViewController.isDoubleSided = true
      if let semanticContentAttribute {
        pageViewController.view.semanticContentAttribute = semanticContentAttribute
      }
    }

    static func controllers(
      primary: UIViewController,
      animated: Bool,
      in pageViewController: UIPageViewController,
      makeBackside: () -> UIViewController
    ) -> [UIViewController] {
      if requiredControllerCount(in: pageViewController, animated: animated) <= 1 {
        return [primary]
      }
      return [primary, makeBackside()]
    }

    static func safeSetViewControllers(
      _ requestedControllers: [UIViewController],
      on pageViewController: UIPageViewController,
      direction: UIPageViewController.NavigationDirection,
      animated: Bool,
      completion: ((Bool) -> Void)? = nil
    ) {
      assert(Thread.isMainThread)
      let controllers = normalizedControllers(
        requestedControllers,
        in: pageViewController,
        animated: animated
      )
      guard !controllers.isEmpty else {
        completion?(false)
        return
      }
      pageViewController.setViewControllers(
        controllers,
        direction: direction,
        animated: animated,
        completion: completion
      )
    }

    static func placeholderControllers(
      in pageViewController: UIPageViewController,
      backgroundColor: UIColor = .clear
    ) -> [UIViewController] {
      normalizedControllers(
        [placeholderController(backgroundColor: backgroundColor)],
        in: pageViewController,
        animated: false
      )
    }

    private static func requiredControllerCount(
      in pageViewController: UIPageViewController,
      animated: Bool
    ) -> Int {
      if pageViewController.spineLocation == .mid {
        return 2
      }
      if animated && pageViewController.isDoubleSided {
        return 2
      }
      return 1
    }

    private static func normalizedControllers(
      _ requestedControllers: [UIViewController],
      in pageViewController: UIPageViewController,
      animated: Bool
    ) -> [UIViewController] {
      guard let primary = requestedControllers.first else { return [] }
      if requiredControllerCount(in: pageViewController, animated: animated) <= 1 {
        return [primary]
      }
      if requestedControllers.count >= 2 {
        return Array(requestedControllers.prefix(2))
      }
      return [primary, fallbackCompanionController(matching: primary)]
    }

    private static func fallbackCompanionController(matching primary: UIViewController) -> UIViewController {
      let fallback = UIViewController()
      fallback.view.backgroundColor = primary.isViewLoaded ? primary.view.backgroundColor : .clear
      return fallback
    }

    private static func placeholderController(backgroundColor: UIColor) -> UIViewController {
      let placeholder = UIViewController()
      placeholder.view.backgroundColor = backgroundColor
      return placeholder
    }
  }
#endif
