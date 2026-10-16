#if os(macOS)
  import AppKit

  @MainActor
  final class NativeCoverContainerView: NSView {
    let slotViews = [NativeCoverSlotView(), NativeCoverSlotView(), NativeCoverSlotView()]
    var onDidLayout: (() -> Void)?

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
      super.layout()
      slotViews.forEach { $0.frame = bounds }
      onDidLayout?()
    }

    func prepareForDismantle() {
      slotViews.forEach { $0.prepareForDismantle() }
      onDidLayout = nil
    }

    private func setupUI() {
      wantsLayer = true
      layer?.masksToBounds = true

      slotViews.forEach { slotView in
        slotView.autoresizingMask = [.width, .height]
        slotView.frame = bounds
        addSubview(slotView)
      }
    }
  }
#endif
