//
// EpubScrubGestureUIView.swift
//
//

#if os(iOS)
  import UIKit

  /// Full-width long-press pan surface for the EPUB progress scrubber.
  ///
  /// The view's bounds stay constant across the expand/collapse animation so
  /// `location(in:)` never shifts mid-gesture; hit-testing is restricted to the
  /// resting track until a scrub begins, leaving the surrounding area open to
  /// the reader's tap zones.
  final class EpubScrubGestureUIView: UIView {
    var restingTrackWidth: CGFloat = 0
    var isScrubbing = false

    var previewAtPoint: ((CGFloat) -> EpubScrubPreview?)?
    var onBegan: ((EpubScrubPreview) -> Void)?
    var onChanged: ((EpubScrubPreview) -> Void)?
    var onEnded: ((EpubScrubPreview?) -> Void)?
    var onCancelled: (() -> Void)?

    var interfaceStyle: UIUserInterfaceStyle = .unspecified {
      didSet { calloutView.overrideUserInterfaceStyle = interfaceStyle }
    }

    private let calloutView = EpubScrubCalloutView()

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
      recognizer.minimumPressDuration = 0.25
      addGestureRecognizer(recognizer)
      isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
      guard bounds.width > 0, bounds.height > 0 else { return false }
      if isScrubbing {
        return bounds.contains(point)
      }
      let width = min(max(0, restingTrackWidth), bounds.width)
      let hitRect = CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
      return hitRect.contains(point)
    }

    func cancelActiveScrub() {
      guard calloutView.superview != nil else { return }
      calloutView.dismiss(animated: false)
      onCancelled?()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
      let x = recognizer.location(in: self).x
      switch recognizer.state {
      case .began:
        guard let preview = previewAtPoint?(x), let host = window else { return }
        calloutView.overrideUserInterfaceStyle = interfaceStyle
        calloutView.present(
          in: host,
          preview: preview,
          atX: convert(CGPoint(x: x, y: 0), to: host).x,
          aboveY: convert(CGPoint(x: 0, y: bounds.midY - 6), to: host).y
        )
        onBegan?(preview)
      case .changed:
        guard let preview = previewAtPoint?(x), let host = calloutView.superview else { return }
        calloutView.update(
          preview: preview,
          atX: convert(CGPoint(x: x, y: 0), to: host).x,
          aboveY: convert(CGPoint(x: 0, y: bounds.midY - 6), to: host).y,
          in: host
        )
        onChanged?(preview)
      case .ended:
        let preview = previewAtPoint?(x)
        calloutView.dismiss()
        onEnded?(preview)
      case .cancelled, .failed:
        cancelActiveScrub()
      default:
        break
      }
    }
  }
#endif
