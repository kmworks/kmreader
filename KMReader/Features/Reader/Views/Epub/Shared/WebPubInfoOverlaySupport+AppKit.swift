#if os(macOS)
  import AppKit
  import CoreGraphics
  import Foundation

  extension WebPubInfoOverlaySupport {
    @MainActor
    final class AppKitOverlay {
      private weak var containerView: NSView?
      private let topLeadingLabel: NSTextField
      private let topCenterLabel: NSTextField
      private let topTrailingLabel: NSTextField
      private let bottomLeadingLabel: NSTextField
      private let bottomCenterLabel: NSTextField
      private let bottomTrailingLabel: NSTextField
      private let bottomProgressTrackView: NSView
      private let bottomProgressFillView: NSView
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
        containerView: NSView,
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
        bottomProgressTrackView = NSView()
        bottomProgressTrackView.translatesAutoresizingMaskIntoConstraints = false
        bottomProgressTrackView.wantsLayer = true
        bottomProgressTrackView.layer?.cornerRadius = 1.5
        bottomProgressTrackView.layer?.shadowColor = NSColor.black.cgColor
        bottomProgressTrackView.layer?.shadowOpacity = 0.45
        bottomProgressTrackView.layer?.shadowRadius = 3
        bottomProgressTrackView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        bottomProgressTrackView.alphaValue = 0

        bottomProgressFillView = NSView()
        bottomProgressFillView.translatesAutoresizingMaskIntoConstraints = false
        bottomProgressFillView.wantsLayer = true
        bottomProgressFillView.layer?.cornerRadius = 1.5
        bottomProgressFillView.alphaValue = 0
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
          topLeadingLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: topOffset),
          topLeadingLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
          topLeadingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),

          topCenterLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: topOffset),
          topCenterLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
          topCenterLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.45),
          topCenterLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topLeadingLabel.trailingAnchor, constant: 8),

          topTrailingLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: topOffset),
          topTrailingLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
          topTrailingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),
          topTrailingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topCenterLabel.trailingAnchor, constant: 8),

          bottomLeadingLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: bottomConstant),
          bottomLeadingLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
          bottomLeadingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),

          bottomCenterLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: bottomConstant),
          bottomCenterLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
          bottomCenterLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.45),
          bottomCenterLabel.leadingAnchor.constraint(
            greaterThanOrEqualTo: bottomLeadingLabel.trailingAnchor, constant: 8),

          bottomTrailingLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: bottomConstant),
          bottomTrailingLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
          bottomTrailingLabel.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.34),
          bottomTrailingLabel.leadingAnchor.constraint(
            greaterThanOrEqualTo: bottomCenterLabel.trailingAnchor, constant: 8),

          bottomProgressTrackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
          bottomProgressTrackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
          bottomProgressTrackView.bottomAnchor.constraint(
            equalTo: containerView.bottomAnchor, constant: min(CGFloat(0), bottomConstant + 6)),
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
        let labelColor = (NSColor(hex: theme.textColorHex) ?? .labelColor).withAlphaComponent(0.6)
        for label in [
          topLeadingLabel, topCenterLabel, topTrailingLabel, bottomLeadingLabel, bottomCenterLabel,
          bottomTrailingLabel,
        ] {
          label.textColor = labelColor
        }
        bottomProgressTrackView.layer?.backgroundColor = labelColor.withAlphaComponent(0.18).cgColor
        bottomProgressFillView.layer?.backgroundColor = labelColor.withAlphaComponent(0.85).cgColor
      }

      func update(content: Content, animated: Bool) {
        guard content != currentContent else { return }
        let previousContent = currentContent
        currentContent = content
        contentUpdateToken += 1
        let token = contentUpdateToken

        // The track is symmetric, so mirroring it moves the leading-anchored
        // fill to the trailing edge for RTL publications.
        bottomProgressTrackView.layer?.setAffineTransform(
          CGAffineTransform(scaleX: content.isRTL ? -1 : 1, y: 1))

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
        to label: NSTextField,
        animated: Bool,
        token: Int
      ) {
        guard animated else {
          apply(entry: entry, to: label)
          return
        }

        let text = entry.text ?? ""

        if previousEntry.isVisible, entry.isVisible {
          guard label.stringValue != text else {
            label.alphaValue = 1.0
            return
          }

          label.alphaValue = 1.0
          crossDissolveText(text, on: label)
          return
        }

        if entry.isVisible {
          setText(text, on: label)
          animateAlpha(1.0, on: label)
          return
        }

        animateAlpha(0.0, on: label) {
          guard token == self.contentUpdateToken, !entry.isVisible, label.alphaValue == 0.0 else {
            return
          }
          self.setText("", on: label)
        }
      }

      private func apply(entry: Entry, to label: NSTextField) {
        setText(entry.text ?? "", on: label)
        label.alphaValue = entry.isVisible ? 1.0 : 0.0
      }

      private func crossDissolveText(_ text: String, on label: NSTextField) {
        let transition = CATransition()
        transition.duration = 0.18
        transition.type = .fade
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        label.layer?.add(transition, forKey: "textCrossDissolve")
        setText(text, on: label)
      }

      private func setText(_ text: String, on label: NSTextField) {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0
          context.allowsImplicitAnimation = false
          label.stringValue = text
          label.superview?.layoutSubtreeIfNeeded()
        }
      }

      private func animateAlpha(
        _ alphaValue: CGFloat,
        on label: NSTextField,
        completion: (@MainActor @Sendable () -> Void)? = nil
      ) {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.18
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          label.animator().alphaValue = alphaValue
        } completionHandler: {
          guard let completion else { return }
          Task { @MainActor in
            completion()
          }
        }
      }

      private func updateProgressBar(progress: Double?, animated: Bool) {
        containerView?.layoutSubtreeIfNeeded()
        let visible = progress != nil
        let normalized = min(max(progress ?? 0, 0), 1)
        let trackWidth = bottomProgressTrackView.bounds.width
        let fillWidth = max(trackWidth * normalized, normalized > 0 ? 4 : 0)
        let updates = {
          self.bottomProgressFillWidthConstraint.constant = fillWidth
          self.bottomProgressTrackView.alphaValue = visible ? 1.0 : 0.0
          self.bottomProgressFillView.alphaValue = visible ? 1.0 : 0.0
          self.containerView?.layoutSubtreeIfNeeded()
        }

        guard animated else {
          updates()
          return
        }

        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.18
          context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
          updates()
        }
      }

      private static func makeLabel(
        fontSize: CGFloat,
        alignment: NSTextAlignment,
        monospaced: Bool = false
      ) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.wantsLayer = true
        label.lineBreakMode = .byTruncatingTail
        label.alignment = alignment
        label.alphaValue = 0
        label.font =
          monospaced
          ? .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
          : .systemFont(ofSize: fontSize)
        return label
      }
    }
  }
#endif
