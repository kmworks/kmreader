//
// PageCurlBacksideViewController.swift
//

#if os(iOS)
  import UIKit

  final class PageCurlBacksideViewController: UIViewController {
    struct Style {
      let baseColor: UIColor
      let fillOpacity: CGFloat
      let dimOpacity: CGFloat

      init(
        baseColor: UIColor,
        fillOpacity: CGFloat = 0.95,
        dimOpacity: CGFloat = 0
      ) {
        self.baseColor = baseColor
        self.fillOpacity = Self.clamp(fillOpacity)
        self.dimOpacity = Self.clamp(dimOpacity)
      }

      var renderedColor: UIColor {
        baseColor.withAlphaComponent(fillOpacity)
      }

      private static func clamp(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
      }
    }

    enum MirrorAxis {
      case horizontal
      case vertical

      var transform: CGAffineTransform {
        switch self {
        case .horizontal:
          return CGAffineTransform(scaleX: -1, y: 1)
        case .vertical:
          return CGAffineTransform(scaleX: 1, y: -1)
        }
      }
    }

    struct MirroredSnapshot {
      let view: UIView
      let axis: MirrorAxis
    }

    let destinationToken: String
    private var style: Style
    private var mirroredSnapshot: MirroredSnapshot?
    private let snapshotContainerView = UIView()
    private var activeSnapshotView: UIView?
    private let dimView = UIView()

    init(
      destinationToken: String,
      style: Style,
      mirroredSnapshot: MirroredSnapshot? = nil
    ) {
      self.destinationToken = destinationToken
      self.style = style
      self.mirroredSnapshot = mirroredSnapshot
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
      let baseView = UIView()
      baseView.backgroundColor = .clear

      snapshotContainerView.translatesAutoresizingMaskIntoConstraints = false
      snapshotContainerView.isUserInteractionEnabled = false
      snapshotContainerView.clipsToBounds = true
      baseView.addSubview(snapshotContainerView)

      dimView.translatesAutoresizingMaskIntoConstraints = false
      dimView.isUserInteractionEnabled = false
      baseView.addSubview(dimView)
      NSLayoutConstraint.activate([
        snapshotContainerView.topAnchor.constraint(equalTo: baseView.topAnchor),
        snapshotContainerView.leadingAnchor.constraint(equalTo: baseView.leadingAnchor),
        snapshotContainerView.trailingAnchor.constraint(equalTo: baseView.trailingAnchor),
        snapshotContainerView.bottomAnchor.constraint(equalTo: baseView.bottomAnchor),
        dimView.topAnchor.constraint(equalTo: baseView.topAnchor),
        dimView.leadingAnchor.constraint(equalTo: baseView.leadingAnchor),
        dimView.trailingAnchor.constraint(equalTo: baseView.trailingAnchor),
        dimView.bottomAnchor.constraint(equalTo: baseView.bottomAnchor),
      ])
      view = baseView
      applyStyle()
      applyMirroredSnapshot()
    }

    func updateStyle(_ style: Style) {
      self.style = style
      if isViewLoaded {
        applyStyle()
      }
    }

    // The mirrored content may only become renderable after the session starts
    // (an EPUB backward flip captures the target page once the live view scrolls to it).
    func updateMirroredSnapshot(_ mirroredSnapshot: MirroredSnapshot) {
      self.mirroredSnapshot = mirroredSnapshot
      if isViewLoaded {
        applyMirroredSnapshot()
      }
    }

    private func applyStyle() {
      view.backgroundColor = style.renderedColor
      dimView.backgroundColor = UIColor.black.withAlphaComponent(style.dimOpacity)
    }

    private func applyMirroredSnapshot() {
      activeSnapshotView?.removeFromSuperview()
      activeSnapshotView = nil

      guard let mirroredSnapshot else {
        snapshotContainerView.isHidden = true
        return
      }

      let snapshotView = mirroredSnapshot.view
      snapshotView.translatesAutoresizingMaskIntoConstraints = false
      snapshotView.isUserInteractionEnabled = false
      snapshotContainerView.addSubview(snapshotView)
      NSLayoutConstraint.activate([
        snapshotView.topAnchor.constraint(equalTo: snapshotContainerView.topAnchor),
        snapshotView.leadingAnchor.constraint(equalTo: snapshotContainerView.leadingAnchor),
        snapshotView.trailingAnchor.constraint(equalTo: snapshotContainerView.trailingAnchor),
        snapshotView.bottomAnchor.constraint(equalTo: snapshotContainerView.bottomAnchor),
      ])
      snapshotView.transform = mirroredSnapshot.axis.transform
      snapshotContainerView.isHidden = false
      activeSnapshotView = snapshotView
    }

    static func makeMirroredSnapshot(
      from sourceController: UIViewController,
      axis: MirrorAxis
    ) -> MirroredSnapshot? {
      guard sourceController.isViewLoaded else { return nil }
      guard let sourceView = sourceController.view else { return nil }
      sourceView.layoutIfNeeded()
      let bounds = sourceView.bounds
      guard bounds.width > 1, bounds.height > 1 else { return nil }

      // For onscreen views, a direct snapshot is fast and avoids extra rendering work.
      if sourceView.window != nil,
        let snapshotView = sourceView.snapshotView(afterScreenUpdates: false)
      {
        return MirroredSnapshot(view: snapshotView, axis: axis)
      }

      // For offscreen/unrendered views, render the layer directly to avoid
      // triggering SwiftUI/AttributeGraph updates during tap-driven transitions.
      let format = UIGraphicsImageRendererFormat.preferred()
      format.opaque = false
      format.scale = sourceView.window?.screen.scale ?? UIScreen.main.scale
      let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
      let image = renderer.image { context in
        sourceView.layer.render(in: context.cgContext)
      }
      let imageView = UIImageView(image: image)
      imageView.contentMode = .scaleToFill
      imageView.clipsToBounds = true
      return MirroredSnapshot(view: imageView, axis: axis)
    }

    static func makeMirroredSnapshot(from image: UIImage, axis: MirrorAxis) -> MirroredSnapshot {
      let imageView = UIImageView(image: image)
      imageView.contentMode = .scaleToFill
      imageView.clipsToBounds = true
      return MirroredSnapshot(view: imageView, axis: axis)
    }

    static func applyStyle(_ style: Style, to pageViewController: UIPageViewController) {
      let color = style.renderedColor
      pageViewController.view.backgroundColor = color
      for subview in pageViewController.view.subviews {
        subview.backgroundColor = color
      }
    }
  }
#endif
