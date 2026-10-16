#if os(iOS)
  import CoreGraphics
  import Foundation
  import UIKit

  extension WebPubInfoOverlaySupport {
    @MainActor
    final class UIKitOverlay {
      private weak var containerView: UIView?
      private let topLeadingLabel: UILabel
      private let topCenterLabel: UILabel
      private let topTrailingLabel: UILabel
      private let bottomLeadingLabel: UILabel
      private let bottomCenterLabel: UILabel
      private let bottomTrailingLabel: UILabel
      private let bottomProgressTrackView: UIView
      private let bottomProgressFillView: UIView
      private let bottomProgressFillWidthConstraint: NSLayoutConstraint
      private var contentUpdateToken = 0
      private var currentContent = Content(
        showingControls: false,
        topLeading: .hidden,
        topCenter: .hidden,
        topTrailing: .hidden,
        bottomLeading: .hidden,
        bottomCenter: .hidden,
        bottomTrailing: .hidden,
        bottomProgress: nil,
        isRTL: false
      )

      init(
        containerView: UIView,
        topAnchor: NSLayoutYAxisAnchor,
        bottomAnchor: NSLayoutYAxisAnchor,
        topOffset: CGFloat,
        bottomOffset: CGFloat,
        theme: ReaderTheme
      ) {
        self.containerView = containerView
        topLeadingLabel = Self.makeLabel(fontSize: 14, alignment: .left)
        topCenterLabel = Self.makeLabel(fontSize: 14, alignment: .center)
        topTrailingLabel = Self.makeLabel(fontSize: 14, alignment: .right)
        bottomLeadingLabel = Self.makeLabel(fontSize: 12, alignment: .left)
        bottomCenterLabel = Self.makeLabel(fontSize: 12, alignment: .center, monospaced: true)
        bottomTrailingLabel = Self.makeLabel(fontSize: 12, alignment: .right, monospaced: true)
        bottomProgressTrackView = UIView()
        bottomProgressTrackView.translatesAutoresizingMaskIntoConstraints = false
        bottomProgressTrackView.layer.cornerRadius = 1.5
        bottomProgressTrackView.layer.shadowColor = UIColor.black.cgColor
        bottomProgressTrackView.layer.shadowOpacity = 0.45
        bottomProgressTrackView.layer.shadowRadius = 3
        bottomProgressTrackView.layer.shadowOffset = CGSize(width: 0, height: 1)
        bottomProgressTrackView.clipsToBounds = false
        bottomProgressTrackView.isUserInteractionEnabled = false
        bottomProgressTrackView.alpha = 0

        bottomProgressFillView = UIView()
        bottomProgressFillView.translatesAutoresizingMaskIntoConstraints = false
        bottomProgressFillView.layer.cornerRadius = 1.5
        bottomProgressFillView.clipsToBounds = true
        bottomProgressFillView.isUserInteractionEnabled = false
        bottomProgressFillView.alpha = 0
        bottomProgressTrackView.addSubview(bottomProgressFillView)
        bottomProgressFillWidthConstraint = bottomProgressFillView.widthAnchor.constraint(equalToConstant: 0)

        let bottomConstant = -bottomOffset
        [
          topLeadingLabel, topCenterLabel, topTrailingLabel, bottomLeadingLabel, bottomCenterLabel,
          bottomTrailingLabel,
          bottomProgressTrackView,
        ]
        .forEach(containerView.addSubview)

        NSLayoutConstraint.activate([
          topLeadingLabel.topAnchor.constraint(equalTo: topAnchor, constant: topOffset),
          topLeadingLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
          topLeadingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),

          topCenterLabel.topAnchor.constraint(equalTo: topAnchor, constant: topOffset),
          topCenterLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
          topCenterLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.45),
          topCenterLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topLeadingLabel.trailingAnchor, constant: 8),

          topTrailingLabel.topAnchor.constraint(equalTo: topAnchor, constant: topOffset),
          topTrailingLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
          topTrailingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),
          topTrailingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topCenterLabel.trailingAnchor, constant: 8),

          bottomLeadingLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: bottomConstant),
          bottomLeadingLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
          bottomLeadingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),

          bottomCenterLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: bottomConstant),
          bottomCenterLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
          bottomCenterLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.45),
          bottomCenterLabel.leadingAnchor.constraint(
            greaterThanOrEqualTo: bottomLeadingLabel.trailingAnchor, constant: 8),

          bottomTrailingLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: bottomConstant),
          bottomTrailingLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
          bottomTrailingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),
          bottomTrailingLabel.leadingAnchor.constraint(
            greaterThanOrEqualTo: bottomCenterLabel.trailingAnchor, constant: 8),

          bottomProgressTrackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
          bottomProgressTrackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
          bottomProgressTrackView.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: min(CGFloat(0), bottomConstant + 6)),
          bottomProgressTrackView.heightAnchor.constraint(equalToConstant: 3),

          bottomProgressFillView.leadingAnchor.constraint(equalTo: bottomProgressTrackView.leadingAnchor),
          bottomProgressFillView.topAnchor.constraint(equalTo: bottomProgressTrackView.topAnchor),
          bottomProgressFillView.bottomAnchor.constraint(equalTo: bottomProgressTrackView.bottomAnchor),
          bottomProgressFillWidthConstraint,
        ])

        bottomLeadingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bottomLeadingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomTrailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomTrailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        bottomCenterLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomCenterLabel.setContentHuggingPriority(.required, for: .horizontal)
        topLeadingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topLeadingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topTrailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        topTrailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        topCenterLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        topCenterLabel.setContentHuggingPriority(.required, for: .horizontal)

        apply(theme: theme)
      }

      func apply(theme: ReaderTheme) {
        let labelColor = theme.uiColorText.withAlphaComponent(0.6)
        for label in [
          topLeadingLabel, topCenterLabel, topTrailingLabel, bottomLeadingLabel, bottomCenterLabel,
          bottomTrailingLabel,
        ] {
          label.textColor = labelColor
        }
        bottomProgressTrackView.backgroundColor = theme.uiColorText.withAlphaComponent(0.18)
        bottomProgressFillView.backgroundColor = theme.uiColorText.withAlphaComponent(0.85)
      }

      func update(content: Content, animated: Bool) {
        guard content != currentContent else { return }
        let previousContent = currentContent
        currentContent = content
        contentUpdateToken += 1
        let token = contentUpdateToken

        // The track is symmetric, so mirroring it moves the leading-anchored
        // fill to the trailing edge for RTL publications.
        bottomProgressTrackView.transform = CGAffineTransform(scaleX: content.isRTL ? -1 : 1, y: 1)

        apply(
          entry: content.topLeading,
          previousEntry: previousContent.topLeading,
          to: topLeadingLabel,
          animated: animated,
          token: token
        )
        apply(
          entry: content.topCenter,
          previousEntry: previousContent.topCenter,
          to: topCenterLabel,
          animated: animated,
          token: token
        )
        apply(
          entry: content.topTrailing,
          previousEntry: previousContent.topTrailing,
          to: topTrailingLabel,
          animated: animated,
          token: token
        )
        apply(
          entry: content.bottomLeading,
          previousEntry: previousContent.bottomLeading,
          to: bottomLeadingLabel,
          animated: animated,
          token: token
        )
        apply(
          entry: content.bottomCenter,
          previousEntry: previousContent.bottomCenter,
          to: bottomCenterLabel,
          animated: animated,
          token: token
        )
        apply(
          entry: content.bottomTrailing,
          previousEntry: previousContent.bottomTrailing,
          to: bottomTrailingLabel,
          animated: animated,
          token: token
        )
        updateProgressBar(progress: content.bottomProgress, animated: animated)
      }

      private func apply(
        entry: Entry,
        previousEntry: Entry,
        to label: UILabel,
        animated: Bool,
        token: Int
      ) {
        guard animated else {
          apply(entry: entry, to: label)
          return
        }

        let text = entry.text ?? ""

        if previousEntry.isVisible, entry.isVisible {
          guard label.text != text else {
            label.alpha = 1.0
            return
          }

          label.alpha = 1.0
          UIView.transition(
            with: label,
            duration: 0.18,
            options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState]
          ) {
            UIView.performWithoutAnimation {
              label.text = text
              label.superview?.layoutIfNeeded()
            }
          }
          return
        }

        if entry.isVisible {
          UIView.performWithoutAnimation {
            label.text = text
            label.superview?.layoutIfNeeded()
          }
          UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
          ) {
            label.alpha = 1.0
          }
          return
        }

        UIView.animate(
          withDuration: 0.18,
          delay: 0,
          options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
          label.alpha = 0.0
        } completion: { _ in
          guard token == self.contentUpdateToken, !entry.isVisible, label.alpha == 0.0 else { return }
          UIView.performWithoutAnimation {
            label.text = ""
            label.superview?.layoutIfNeeded()
          }
        }
      }

      private func apply(entry: Entry, to label: UILabel) {
        label.text = entry.text ?? ""
        label.alpha = entry.isVisible ? 1.0 : 0.0
      }

      private func updateProgressBar(progress: Double?, animated: Bool) {
        containerView?.layoutIfNeeded()
        let visible = progress != nil
        let normalized = min(max(progress ?? 0, 0), 1)
        let trackWidth = bottomProgressTrackView.bounds.width
        let fillWidth = max(trackWidth * normalized, normalized > 0 ? 4 : 0)
        let updates = {
          self.bottomProgressFillWidthConstraint.constant = fillWidth
          self.bottomProgressTrackView.alpha = visible ? 1.0 : 0.0
          self.bottomProgressFillView.alpha = visible ? 1.0 : 0.0
          self.containerView?.layoutIfNeeded()
        }
        if animated {
          UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: updates
          )
        } else {
          updates()
        }
      }

      private static func makeLabel(
        fontSize: CGFloat,
        alignment: NSTextAlignment,
        monospaced: Bool = false
      ) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.font =
          monospaced
          ? UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
          : .systemFont(ofSize: fontSize)
        label.textAlignment = alignment
        label.isUserInteractionEnabled = false
        label.alpha = 0
        return label
      }
    }
  }
#endif
