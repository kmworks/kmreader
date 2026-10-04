//
// CircularProgressView.swift
//
//

#if os(iOS) || os(tvOS)
  import UIKit

  /// Apple Books-style download progress: a thin track ring with a solid pie
  /// sector growing clockwise from the top.
  final class CircularProgressView: UIView {
    /// The pie never renders empty: a sliver keeps the ring visibly alive.
    private static let minimumProgress: Double = 0.027

    var progress: Double = 0 {
      didSet { progressDidChange() }
    }

    var color: UIColor = .label {
      didSet { updateColors() }
    }

    private let trackLayer = CAShapeLayer()
    private let pieLayer = CAShapeLayer()

    private var displayedProgress: Double = 0
    private var tweenFrom: Double = 0
    private var tweenTo: Double = 0
    private var tweenStart: CFTimeInterval = 0
    private var tweenDuration: TimeInterval = 0
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      trackLayer.fillColor = nil
      pieLayer.strokeColor = nil
      layer.addSublayer(trackLayer)
      layer.addSublayer(pieLayer)
      updateColors()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func willMove(toSuperview newSuperview: UIView?) {
      super.willMove(toSuperview: newSuperview)
      // CADisplayLink retains its target; dropping the link on detach breaks the cycle.
      if newSuperview == nil {
        stopTween()
      }
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      guard bounds.width > 0, bounds.height > 0 else { return }
      let side = min(bounds.width, bounds.height)
      let lineWidth: CGFloat = 1.5
      let ringRect = CGRect(
        x: (bounds.width - side) / 2,
        y: (bounds.height - side) / 2,
        width: side,
        height: side
      ).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
      trackLayer.frame = bounds
      trackLayer.path = UIBezierPath(ovalIn: ringRect).cgPath
      trackLayer.lineWidth = lineWidth
      pieLayer.frame = bounds
      renderPie()
    }

    private func progressDidChange() {
      let target = min(max(progress, Self.minimumProgress), 1)
      guard target != tweenTo || displayLink == nil else { return }
      let delta = abs(target - displayedProgress)
      guard delta > 0 else { return }
      tweenFrom = displayedProgress
      tweenTo = target
      tweenStart = CACurrentMediaTime()
      tweenDuration = ProgressTween.duration(forDelta: delta)
      if displayLink == nil {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
      }
    }

    @objc private func tick(_ link: CADisplayLink) {
      let elapsed = CACurrentMediaTime() - tweenStart
      let raw = tweenDuration > 0 ? min(elapsed / tweenDuration, 1) : 1
      let eased = tweenDuration > 0.2 ? ProgressTween.easeOutCubic(raw) : raw
      displayedProgress = tweenFrom + (tweenTo - tweenFrom) * eased
      renderPie()
      if raw >= 1 {
        stopTween()
      }
    }

    private func stopTween() {
      displayLink?.invalidate()
      displayLink = nil
      displayedProgress = tweenTo
      renderPie()
    }

    private func renderPie() {
      let clamped = min(max(displayedProgress, Self.minimumProgress), 1)
      guard bounds.width > 0 else {
        pieLayer.path = nil
        return
      }
      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      let radius = (min(bounds.width, bounds.height) - 3) / 2
      let path = UIBezierPath()
      path.move(to: center)
      path.addArc(
        withCenter: center,
        radius: radius,
        startAngle: -.pi / 2,
        endAngle: -.pi / 2 + 2 * .pi * clamped,
        clockwise: true
      )
      path.close()
      pieLayer.path = path.cgPath
    }

    private func updateColors() {
      trackLayer.strokeColor = color.withAlphaComponent(0.3).cgColor
      pieLayer.fillColor = color.cgColor
    }
  }
#elseif os(macOS)
  import AppKit

  /// Apple Books-style download progress: a thin track ring with a solid pie
  /// sector growing clockwise from the top.
  final class CircularProgressView: NSView {
    /// The pie never renders empty: a sliver keeps the ring visibly alive.
    private static let minimumProgress: Double = 0.027

    var progress: Double = 0 {
      didSet { progressDidChange() }
    }

    var color: NSColor = .labelColor {
      didSet { updateColors() }
    }

    private let trackLayer = CAShapeLayer()
    private let pieLayer = CAShapeLayer()

    private var displayedProgress: Double = 0
    private var tweenFrom: Double = 0
    private var tweenTo: Double = 0
    private var tweenStart: CFTimeInterval = 0
    private var tweenDuration: TimeInterval = 0
    private var tweenLink: CADisplayLink?

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      trackLayer.fillColor = nil
      pieLayer.strokeColor = nil
      layer?.addSublayer(trackLayer)
      layer?.addSublayer(pieLayer)
      updateColors()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    // Match UIKit's y-down coordinates so both platforms share the same arc math.
    override var isFlipped: Bool {
      true
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
      super.viewWillMove(toSuperview: newSuperview)
      // CADisplayLink retains its target; dropping the link on detach breaks the cycle.
      if newSuperview == nil {
        stopTween()
      }
    }

    override func layout() {
      super.layout()
      guard bounds.width > 0, bounds.height > 0 else { return }
      let side = min(bounds.width, bounds.height)
      let lineWidth: CGFloat = 1.5
      let ringRect = CGRect(
        x: (bounds.width - side) / 2,
        y: (bounds.height - side) / 2,
        width: side,
        height: side
      ).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
      trackLayer.frame = bounds
      trackLayer.path = CGPath(ellipseIn: ringRect, transform: nil)
      trackLayer.lineWidth = lineWidth
      pieLayer.frame = bounds
      renderPie()
    }

    private func progressDidChange() {
      let target = min(max(progress, Self.minimumProgress), 1)
      guard target != tweenTo || tweenLink == nil else { return }
      let delta = abs(target - displayedProgress)
      guard delta > 0 else { return }
      tweenFrom = displayedProgress
      tweenTo = target
      tweenStart = CACurrentMediaTime()
      tweenDuration = ProgressTween.duration(forDelta: delta)
      if tweenLink == nil {
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        tweenLink = link
      }
    }

    @objc private func tick(_ link: CADisplayLink) {
      let elapsed = CACurrentMediaTime() - tweenStart
      let raw = tweenDuration > 0 ? min(elapsed / tweenDuration, 1) : 1
      let eased = tweenDuration > 0.2 ? ProgressTween.easeOutCubic(raw) : raw
      displayedProgress = tweenFrom + (tweenTo - tweenFrom) * eased
      renderPie()
      if raw >= 1 {
        stopTween()
      }
    }

    private func stopTween() {
      tweenLink?.invalidate()
      tweenLink = nil
      displayedProgress = tweenTo
      renderPie()
    }

    private func renderPie() {
      let clamped = min(max(displayedProgress, Self.minimumProgress), 1)
      guard bounds.width > 0 else {
        pieLayer.path = nil
        return
      }
      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      let radius = (min(bounds.width, bounds.height) - 3) / 2
      let path = CGMutablePath()
      path.move(to: center)
      path.addArc(
        center: center,
        radius: radius,
        startAngle: -.pi / 2,
        endAngle: -.pi / 2 + 2 * .pi * clamped,
        clockwise: true
      )
      path.closeSubpath()
      pieLayer.path = path
    }

    private func updateColors() {
      trackLayer.strokeColor = color.withAlphaComponent(0.3).cgColor
      pieLayer.fillColor = color.cgColor
    }
  }
#endif
