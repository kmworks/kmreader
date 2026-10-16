#if os(iOS) || os(tvOS)
  import UIKit

  final class NativePagedLayoutAwareCollectionView: UICollectionView {
    var onDidLayout: (() -> Void)?
    /// Lets the owner refuse a paging drag, e.g. one a page's own content
    /// should follow.
    var shouldBeginPan: ((UIPanGestureRecognizer) -> Bool)?

    override func layoutSubviews() {
      super.layoutSubviews()
      onDidLayout?()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer === panGestureRecognizer, let shouldBeginPan,
        !shouldBeginPan(panGestureRecognizer)
      {
        return false
      }
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
  }
#endif
