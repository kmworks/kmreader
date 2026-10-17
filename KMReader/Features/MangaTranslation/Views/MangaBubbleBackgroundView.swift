import Foundation

#if os(iOS) || os(tvOS)
  import UIKit

  final class MangaBubbleBackgroundView: UIView {
    var fillColor: UIColor = .white {
      didSet { if fillColor != oldValue { setNeedsLayout() } }
    }
    var feather: CGFloat = 10 {
      didSet { if feather != oldValue { setNeedsLayout() } }
    }

    private var renderedSize: CGSize?
    private var renderedColor: UIColor?
    private var renderedFeather: CGFloat = 0

    override init(frame: CGRect) {
      super.init(frame: frame)
      isUserInteractionEnabled = false
      backgroundColor = .clear
      layer.contentsGravity = .resize
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      isUserInteractionEnabled = false
      backgroundColor = .clear
      layer.contentsGravity = .resize
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      let size = bounds.size
      guard size.width > 1, size.height > 1 else {
        layer.contents = nil
        renderedSize = nil
        return
      }
      guard
        size != renderedSize || fillColor != renderedColor || feather != renderedFeather
      else { return }
      renderedSize = size
      renderedColor = fillColor
      renderedFeather = feather
      layer.contents = MangaBubbleBackground.blobImage(
        size: size, feather: feather, color: fillColor.cgColor)
    }
  }
#elseif os(macOS)
  import AppKit

  final class MangaBubbleBackgroundView: NSView {
    var fillColor: NSColor = .white {
      didSet { if fillColor != oldValue { needsLayout = true } }
    }
    var feather: CGFloat = 10 {
      didSet { if feather != oldValue { needsLayout = true } }
    }

    private var renderedSize: CGSize?
    private var renderedColor: NSColor?
    private var renderedFeather: CGFloat = 0

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      wantsLayer = true
      layer?.contentsGravity = .resize
    }

    override func layout() {
      super.layout()
      let size = bounds.size
      guard size.width > 1, size.height > 1 else {
        layer?.contents = nil
        renderedSize = nil
        return
      }
      guard
        size != renderedSize || fillColor != renderedColor || feather != renderedFeather
      else { return }
      renderedSize = size
      renderedColor = fillColor
      renderedFeather = feather
      layer?.contents = MangaBubbleBackground.blobImage(
        size: size, feather: feather, color: fillColor.cgColor)
    }
  }
#endif
