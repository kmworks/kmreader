#if os(iOS) || os(tvOS)
  import UIKit

  /// The corner mask must track the image view's own bounds: reading them from
  /// the parent's layout pass races subview frame application and can leave a
  /// stale or missing mask (sharp corners) until the next relayout.
  final class NativeBookCoverImageView: UIImageView {
    var onDidLayout: (() -> Void)?

    override func layoutSubviews() {
      super.layoutSubviews()
      onDidLayout?()
    }
  }
#elseif os(macOS)
  import AppKit

  /// The corner mask must track the image view's own bounds: reading them from
  /// the parent's layout pass races subview frame application and can leave a
  /// stale or missing mask (sharp corners) until the next relayout.
  final class NativeBookCoverImageView: NSImageView {
    var onDidLayout: (() -> Void)?

    override func layout() {
      super.layout()
      onDidLayout?()
    }
  }
#endif
