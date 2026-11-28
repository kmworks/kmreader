//
// EpubScrubCalloutView.swift
//
//

#if os(iOS)
  import UIKit

  /// Floating scrub-destination callout backed by the system glass/material
  /// effect. Positioned directly in window coordinates so it tracks the finger
  /// at touch frequency without presenting a view controller or re-running
  /// SwiftUI layout.
  final class EpubScrubCalloutView: UIView {
    private let effectView: UIVisualEffectView
    private let shapeMask = CAShapeLayer()
    private let rimLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let pageLabel = UILabel()

    private static let cornerRadius: CGFloat = 20
    private static let pointerWidth: CGFloat = 22
    private static let pointerHeight: CGFloat = 9
    private static let horizontalPadding: CGFloat = 18
    private static let verticalPadding: CGFloat = 10
    private static let lineSpacing: CGFloat = 2
    private static let maximumTextWidth: CGFloat = 230
    private static let edgeMargin: CGFloat = 10

    private var pointerOffset: CGFloat = 0
    private var currentTitle: String = ""
    private var currentPage: Int = -1
    private var dismissalToken = 0

    override init(frame: CGRect) {
      let blur = UIBlurEffect(style: .systemMaterial)
      effectView = UIVisualEffectView(effect: blur)
      super.init(frame: frame)
      backgroundColor = .clear
      isUserInteractionEnabled = false

      // UIGlassEffect ignores arbitrary CAShapeLayer masks; UIBlurEffect clips
      // cleanly to the rounded callout + pointer path on every supported iOS.
      effectView.layer.mask = shapeMask
      addSubview(effectView)

      titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
      titleLabel.textAlignment = .center
      titleLabel.lineBreakMode = .byTruncatingTail
      titleLabel.numberOfLines = 1

      pageLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
      pageLabel.textAlignment = .center
      pageLabel.numberOfLines = 1

      titleLabel.textColor = .label
      pageLabel.textColor = .secondaryLabel
      effectView.contentView.addSubview(titleLabel)
      effectView.contentView.addSubview(pageLabel)

      rimLayer.fillColor = UIColor.clear.cgColor
      rimLayer.strokeColor = UIColor.label.withAlphaComponent(0.14).cgColor
      rimLayer.lineWidth = 1
      layer.addSublayer(rimLayer)

      layer.shadowColor = UIColor.black.cgColor
      layer.shadowOpacity = 0.16
      layer.shadowRadius = 12
      layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      effectView.frame = bounds
      rimLayer.frame = bounds
      let bodyHeight = bounds.height - Self.pointerHeight
      let horizontalInset = Self.horizontalPadding
      let titleHeight = titleLabel.font.lineHeight
      let pageHeight = pageLabel.font.lineHeight
      let textHeight = titleHeight + Self.lineSpacing + pageHeight
      let top = (bodyHeight - textHeight) / 2
      let textWidth = max(0, bounds.width - horizontalInset * 2)
      titleLabel.frame = CGRect(x: horizontalInset, y: top, width: textWidth, height: titleHeight)
      pageLabel.frame = CGRect(
        x: horizontalInset,
        y: top + titleHeight + Self.lineSpacing,
        width: textWidth,
        height: pageHeight
      )
      let path = Self.calloutPath(
        bodyRect: CGRect(x: 0, y: 0, width: bounds.width, height: bodyHeight),
        pointerOffset: pointerOffset
      )
      shapeMask.path = path
      rimLayer.path = path
    }

    func update(preview: EpubScrubPreview, atX touchX: CGFloat, aboveY trackTopY: CGFloat, in hostView: UIView) {
      let textChanged = preview.chapterTitle != currentTitle || preview.bookPage != currentPage
      if textChanged {
        let chapterChanged = preview.chapterTitle != currentTitle
        currentTitle = preview.chapterTitle
        currentPage = preview.bookPage
        titleLabel.text = preview.chapterTitle
        pageLabel.text = String(localized: "Page \(preview.bookPage)")
        let targetSize = Self.preferredSize(title: preview.chapterTitle, page: preview.bookPage)
        if chapterChanged, bounds.width > 0, abs(bounds.width - targetSize.width) > 1 {
          UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.bounds = CGRect(origin: .zero, size: targetSize)
          }
        } else if bounds.size != targetSize {
          bounds = CGRect(origin: .zero, size: targetSize)
        }
      }

      let width = bounds.width
      let height = bounds.height
      let minCenter = Self.edgeMargin + width / 2
      let maxCenter = max(minCenter, hostView.bounds.width - Self.edgeMargin - width / 2)
      let centerX = min(max(touchX, minCenter), maxCenter)
      pointerOffset = touchX - centerX
      let centerY = trackTopY - 6 - height / 2
      center = CGPoint(x: centerX, y: centerY)

      // Do not force layoutIfNeeded() here: Core Animation drives layoutSubviews
      // across the bounds animation frames. Only the mask follows the pointer
      // directly when bounds are not changing.
      if !textChanged {
        let bodyRect = CGRect(x: 0, y: 0, width: width, height: height - Self.pointerHeight)
        let path = Self.calloutPath(bodyRect: bodyRect, pointerOffset: pointerOffset)
        shapeMask.path = path
        rimLayer.path = path
      } else {
        setNeedsLayout()
      }
    }

    func present(in hostView: UIView, preview: EpubScrubPreview, atX touchX: CGFloat, aboveY trackTopY: CGFloat) {
      dismissalToken += 1
      layer.removeAllAnimations()
      if superview !== hostView {
        removeFromSuperview()
        currentTitle = ""
        currentPage = -1
        update(preview: preview, atX: touchX, aboveY: trackTopY, in: hostView)
        layoutIfNeeded()
        hostView.addSubview(self)
      } else {
        update(preview: preview, atX: touchX, aboveY: trackTopY, in: hostView)
      }
      alpha = 0
      transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
      UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
        self.alpha = 1
        self.transform = .identity
      }
    }

    func dismiss(animated: Bool = true) {
      dismissalToken += 1
      let token = dismissalToken
      guard superview != nil else { return }
      guard animated else {
        layer.removeAllAnimations()
        removeFromSuperview()
        currentTitle = ""
        currentPage = -1
        return
      }
      UIView.animate(
        withDuration: 0.16,
        delay: 0,
        options: [.curveEaseIn, .beginFromCurrentState]
      ) {
        self.alpha = 0
      } completion: { _ in
        // A quick re-press within the fade-out window re-presents this view;
        // stale completions must not detach the active callout.
        guard self.dismissalToken == token else { return }
        self.removeFromSuperview()
        self.currentTitle = ""
        self.currentPage = -1
      }
    }

    private static func preferredSize(title: String, page: Int) -> CGSize {
      let probeTitle = UILabel()
      probeTitle.font = .systemFont(ofSize: 15, weight: .bold)
      probeTitle.text = title
      let probePage = UILabel()
      probePage.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
      probePage.text = String(localized: "Page \(page)")
      let textWidth = min(
        maximumTextWidth,
        max(probeTitle.intrinsicContentSize.width, probePage.intrinsicContentSize.width)
      )
      let bodyHeight =
        verticalPadding * 2 + probeTitle.font.lineHeight + lineSpacing + probePage.font.lineHeight
      return CGSize(
        width: (textWidth + horizontalPadding * 2).rounded(.up),
        height: (bodyHeight + pointerHeight).rounded(.up)
      )
    }

    /// Rounded body with a smooth-shouldered downward pointer that slides along
    /// the flat bottom edge to stay aimed at the touch point.
    private static func calloutPath(bodyRect: CGRect, pointerOffset: CGFloat) -> CGPath {
      let radius = min(cornerRadius, bodyRect.width / 2, bodyRect.height / 2)
      let halfPointer = min(pointerWidth / 2, max(0, bodyRect.width / 2 - radius))
      let maxOffset = max(0, bodyRect.width / 2 - radius - halfPointer)
      let pointerX = bodyRect.midX + min(max(pointerOffset, -maxOffset), maxOffset)
      let tipY = bodyRect.maxY + pointerHeight
      let shoulder: CGFloat = 5

      let path = CGMutablePath()
      path.move(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY))
      path.addLine(to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.minY))
      path.addArc(
        center: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.minY + radius),
        radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: false
      )
      path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - radius))
      path.addArc(
        center: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.maxY - radius),
        radius: radius, startAngle: 0, endAngle: .pi / 2, clockwise: false
      )
      if halfPointer > 0 {
        path.addLine(to: CGPoint(x: pointerX + halfPointer, y: bodyRect.maxY))
        path.addQuadCurve(
          to: CGPoint(x: pointerX, y: tipY),
          control: CGPoint(x: pointerX + shoulder, y: bodyRect.maxY)
        )
        path.addQuadCurve(
          to: CGPoint(x: pointerX - halfPointer, y: bodyRect.maxY),
          control: CGPoint(x: pointerX - shoulder, y: bodyRect.maxY)
        )
      }
      path.addLine(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.maxY))
      path.addArc(
        center: CGPoint(x: bodyRect.minX + radius, y: bodyRect.maxY - radius),
        radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: false
      )
      path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + radius))
      path.addArc(
        center: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY + radius),
        radius: radius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false
      )
      path.closeSubpath()
      return path
    }
  }
#endif
