//
// ShimmerSweepView.swift
//
//

#if os(iOS) || os(tvOS)
  import UIKit

  /// Animated highlight band sweeping across a placeholder surface. The sweep
  /// runs as a render-server Core Animation so no SwiftUI state changes per
  /// frame: a value-driven perpetual animation inside scroll content keeps the
  /// layout engine churning, which after a rotation locks the dashboard's
  /// nested scroll views into a re-layout loop.
  final class ShimmerSweepView: UIView {
    private static let period: Double = 1.3

    var cornerRadius: CGFloat = 0 {
      didSet { setNeedsLayout() }
    }

    private let bandLayer = CAGradientLayer()

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      layer.masksToBounds = true
      bandLayer.startPoint = CGPoint(x: 0, y: 0.5)
      bandLayer.endPoint = CGPoint(x: 1, y: 0.5)
      layer.addSublayer(bandLayer)
      registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
        (self: Self, _: UITraitCollection) in
        self.refreshBand()
      }
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      layer.cornerRadius = cornerRadius
      refreshBand()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      refreshBand()
    }

    private func refreshBand() {
      let band = min(250, bounds.height)
      guard band > 0, bounds.width > 0 else { return }

      #if os(tvOS)
        let background = UIColor.gray
      #else
        let background = UIColor.systemBackground.resolvedColor(with: traitCollection)
      #endif

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      bandLayer.frame = CGRect(x: -band, y: 0, width: band, height: bounds.height)
      bandLayer.colors = [
        background.withAlphaComponent(0).cgColor,
        background.withAlphaComponent(0.4).cgColor,
        background.withAlphaComponent(0).cgColor,
      ]
      CATransaction.commit()

      let sweep = CABasicAnimation(keyPath: "transform.translation.x")
      sweep.fromValue = 0
      sweep.toValue = bounds.width + band
      sweep.duration = Self.period
      sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.38, 0.7, 0.125, 1.0)
      sweep.repeatCount = .infinity
      // Wall-clock phase keeps every visible band sweeping in sync.
      sweep.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: Self.period)
      bandLayer.add(sweep, forKey: "shimmerSweep")
    }
  }
#elseif os(macOS)
  import AppKit

  /// Animated highlight band sweeping across a placeholder surface. The sweep
  /// runs as a render-server Core Animation so no SwiftUI state changes per
  /// frame: a value-driven perpetual animation inside scroll content keeps the
  /// layout engine churning, which after a rotation locks the dashboard's
  /// nested scroll views into a re-layout loop.
  final class ShimmerSweepView: NSView {
    private static let period: Double = 1.3

    var cornerRadius: CGFloat = 0 {
      didSet { needsLayout = true }
    }

    private let bandLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.masksToBounds = true
      bandLayer.startPoint = CGPoint(x: 0, y: 0.5)
      bandLayer.endPoint = CGPoint(x: 1, y: 0.5)
      layer?.addSublayer(bandLayer)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    // The band overlays the whole card; clicks belong to the content below.
    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }

    override func layout() {
      super.layout()
      layer?.cornerRadius = cornerRadius
      refreshBand()
    }

    override func viewDidChangeEffectiveAppearance() {
      super.viewDidChangeEffectiveAppearance()
      refreshBand()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      refreshBand()
    }

    private func refreshBand() {
      let band = min(250, bounds.height)
      guard band > 0, bounds.width > 0 else { return }

      // Dynamic NSColors resolve against the current drawing appearance, not
      // the view's, when converted to CGColor.
      effectiveAppearance.performAsCurrentDrawingAppearance {
        let background = NSColor.controlBackgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bandLayer.frame = CGRect(x: -band, y: 0, width: band, height: bounds.height)
        bandLayer.colors = [
          background.withAlphaComponent(0).cgColor,
          background.withAlphaComponent(0.4).cgColor,
          background.withAlphaComponent(0).cgColor,
        ]
        CATransaction.commit()
      }

      let sweep = CABasicAnimation(keyPath: "transform.translation.x")
      sweep.fromValue = 0
      sweep.toValue = bounds.width + band
      sweep.duration = Self.period
      sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.38, 0.7, 0.125, 1.0)
      sweep.repeatCount = .infinity
      // Wall-clock phase keeps every visible band sweeping in sync.
      sweep.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: Self.period)
      bandLayer.add(sweep, forKey: "shimmerSweep")
    }
  }
#endif
