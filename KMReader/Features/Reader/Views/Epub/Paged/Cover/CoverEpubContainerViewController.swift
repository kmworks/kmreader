#if os(iOS)
  import UIKit

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
