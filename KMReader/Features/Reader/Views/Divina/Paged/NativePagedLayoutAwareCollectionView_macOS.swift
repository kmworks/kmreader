#if os(macOS)
  import AppKit

  final class NativePagedLayoutAwareCollectionView: NSCollectionView {
    var onDidLayout: (() -> Void)?

    override func layout() {
      super.layout()
      onDidLayout?()
    }
  }
#endif
