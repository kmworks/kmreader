#if os(iOS)
  import UIKit

  @MainActor
  final class CurlPageShellViewController: UIViewController {
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

    func unpark() {
      for child in children {
        child.willMove(toParent: nil)
        child.removeFromParent()
      }
      willMove(toParent: nil)
      view.removeFromSuperview()
      removeFromParent()
    }
  }
#endif
