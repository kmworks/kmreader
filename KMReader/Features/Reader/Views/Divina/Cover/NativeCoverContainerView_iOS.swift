#if os(iOS) || os(tvOS)
  import UIKit

  @MainActor
  final class NativeCoverContainerView: UIView {
    let slotViews = [NativeCoverSlotView(), NativeCoverSlotView(), NativeCoverSlotView()]
    var onDidLayout: (() -> Void)?

    override init(frame: CGRect) {
      super.init(frame: frame)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      slotViews.forEach { $0.frame = bounds }
      onDidLayout?()
    }

    func prepareForDismantle() {
      slotViews.forEach { $0.prepareForDismantle() }
      onDidLayout = nil
    }

    private func setupUI() {
      clipsToBounds = true
      isOpaque = true

      slotViews.forEach { slotView in
        slotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        slotView.frame = bounds
        addSubview(slotView)
      }
    }
  }
#endif
