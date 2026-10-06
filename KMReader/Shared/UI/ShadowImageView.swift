//
// ShadowImageView.swift
//
//

import SwiftUI

/// Drop shadow backed by a pre-rendered stretchable image shared by all cards.
/// Per-card layer shadows make the render server blur every card individually,
/// which dominates scroll and resize cost in card grids.
struct ShadowImageView: View {
  let style: ShadowStyle
  let cornerRadius: CGFloat

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let descriptor = ShadowImageDescriptor(
      style: style, cornerRadius: cornerRadius, colorScheme: colorScheme)
    Image(decorative: ShadowImageCache.image(for: descriptor), scale: ShadowImageCache.renderScale)
      .resizable(capInsets: descriptor.capInsets, resizingMode: .stretch)
      .padding(-descriptor.margin)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private struct ShadowImageDescriptor {
  let style: ShadowStyle
  let cornerRadius: CGFloat
  let colorScheme: ColorScheme
  /// How far the corner curve reaches along the core's edges.
  let cornerSpan: CGFloat

  /// The core only casts the shadow; the card covers it. Shrinking it a hair
  /// inside the card bounds keeps coverage from depending on exact shape or
  /// antialiasing matches with the card's clip.
  static let coreInset: CGFloat = 0.5

  init(style: ShadowStyle, cornerRadius: CGFloat, colorScheme: ColorScheme) {
    self.style = style
    self.cornerRadius = cornerRadius
    self.colorScheme = colorScheme
    self.cornerSpan = Self.measureCornerSpan(Self.effectiveRadius(cornerRadius))
  }

  static func effectiveRadius(_ cornerRadius: CGFloat) -> CGFloat {
    max(cornerRadius - coreInset, 0)
  }

  struct Layer {
    let colorName: String
    /// CGContext blur in points — its falloff runs tighter than CALayer's for
    /// the same value, so these don't read as the old shadow radii.
    let blur: CGFloat
    let y: CGFloat
  }

  var layers: [Layer] {
    switch style {
    case .none:
      return []
    case .basic:
      return [Layer(colorName: "shadowNear", blur: 2.5, y: 0)]
    case .platform:
      return [
        Layer(colorName: "shadowFar", blur: 20, y: 8),
        Layer(colorName: "shadowNear", blur: 8, y: 4),
      ]
    }
  }

  /// Deep enough to contain the widest blur plus its offset.
  var margin: CGFloat {
    layers.map { $0.blur + abs($0.y) + 2 }.max() ?? 0
  }

  /// Core edge length: both corner curves plus a straight stretchable center.
  var coreSize: CGFloat {
    2 * (Self.coreInset + cornerSpan + 1) + 24
  }

  var cacheKey: String {
    "\(style)#\(cornerRadius)#\(colorScheme == .dark ? "dark" : "light")"
  }

  var capInsets: EdgeInsets {
    let inset = margin + Self.coreInset + cornerSpan + 1
    return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
  }

  /// Continuous corners start curving about 1.5 radii ahead of the corner,
  /// well beyond the circular tangent point, so cap insets derived from the
  /// nominal radius would stretch part of the curve.
  private static func measureCornerSpan(_ cornerRadius: CGFloat) -> CGFloat {
    guard cornerRadius > 0 else { return 0 }
    let rect = CGRect(
      x: 0, y: 0, width: 4 * cornerRadius + 100, height: 4 * cornerRadius + 100)
    var span = cornerRadius
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .path(in: rect)
      .forEach { element in
        let point: CGPoint
        switch element {
        case .move(let to), .line(let to):
          point = to
        case .quadCurve(let to, _), .curve(let to, _, _):
          point = to
        case .closeSubpath:
          return
        }
        // The path starts mid-edge; only corner-region points are tangents.
        let limit = rect.width / 4
        if point.y <= rect.minY + 0.001 || point.y >= rect.maxY - 0.001 {
          let candidate = min(point.x - rect.minX, rect.maxX - point.x)
          if candidate < limit { span = max(span, candidate) }
        }
        if point.x <= rect.minX + 0.001 || point.x >= rect.maxX - 0.001 {
          let candidate = min(point.y - rect.minY, rect.maxY - point.y)
          if candidate < limit { span = max(span, candidate) }
        }
      }
    return span
  }
}

private enum ShadowImageCache {
  static let renderScale: CGFloat = 2
  private static let cache = NSCache<NSString, CGImage>()
  private static let transparentPixel: CGImage = {
    let context = CGContext(
      data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
  }()

  static func image(for descriptor: ShadowImageDescriptor) -> CGImage {
    let key = descriptor.cacheKey as NSString
    if let cached = cache.object(forKey: key) {
      return cached
    }
    let rendered = render(descriptor)
    cache.setObject(rendered, forKey: key)
    return rendered
  }

  private static func render(_ descriptor: ShadowImageDescriptor) -> CGImage {
    let margin = descriptor.margin
    let core = descriptor.coreSize
    let pointSize = core + margin * 2
    let pixelSize = Int((pointSize * renderScale).rounded())
    guard pixelSize > 0,
      let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return transparentPixel
    }
    // Top-left origin so layer y offsets read as visual-down.
    context.translateBy(x: 0, y: pointSize * renderScale)
    context.scaleBy(x: renderScale, y: -renderScale)

    let inset = ShadowImageDescriptor.coreInset
    let coreRect = CGRect(
      x: margin + inset, y: margin + inset,
      width: core - inset * 2, height: core - inset * 2)
    // Cards clip with SwiftUI's default continuous RoundedRectangle; a
    // circular core would peek out as dark arcs just ahead of each corner.
    let path = RoundedRectangle(
      cornerRadius: ShadowImageDescriptor.effectiveRadius(descriptor.cornerRadius),
      style: .continuous
    )
    .path(in: coreRect)
    .cgPath
    for layer in descriptor.layers {
      context.saveGState()
      // Shadow parameters live in the context's base space (y-up pixels):
      // negate y for visual-down and scale both to pixels.
      context.setShadow(
        offset: CGSize(width: 0, height: -layer.y * renderScale),
        blur: layer.blur * renderScale,
        color: resolve(layer.colorName, in: descriptor.colorScheme))
      context.setFillColor(CGColor(gray: 0, alpha: 1))
      context.addPath(path)
      context.fillPath()
      context.restoreGState()
    }
    return context.makeImage() ?? transparentPixel
  }

  private static func resolve(_ name: String, in scheme: ColorScheme) -> CGColor {
    #if os(macOS)
      var color = NSColor.black.cgColor
      NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?
        .performAsCurrentDrawingAppearance {
          color = NSColor(named: name)?.cgColor ?? color
        }
      return color
    #else
      let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
      return UIColor(named: name)?.resolvedColor(with: traits).cgColor ?? UIColor.black.cgColor
    #endif
  }
}
