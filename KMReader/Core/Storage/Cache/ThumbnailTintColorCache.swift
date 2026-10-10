//
// ThumbnailTintColorCache.swift
//
//

import CoreGraphics
import Foundation
import SwiftUI

/// Cover-tinted background colors for horizontal cards, Apple Books style: the
/// cover's average color, brightness-clamped so white card text stays readable
/// without the card going pitch black. Results are cached per thumbnail; a
/// `.thumbnailDidRefresh` invalidation (via `invalidate`) forces re-extraction.
///
/// MainActor so views can seed their tint synchronously (`cachedColor`) before
/// the first render — the same warm start `ThumbnailImage` gets from
/// `ThumbnailCache.cachedImage`. Only extraction leaves the main actor.
@MainActor
final class ThumbnailTintColorCache {
  static let shared = ThumbnailTintColorCache()

  private var colors: [String: Color] = [:]
  private var inFlight: [String: Task<Color?, Never>] = [:]

  private init() {}

  func cachedColor(id: String, type: ThumbnailType) -> Color? {
    colors[Self.key(id: id, type: type)]
  }

  func color(id: String, type: ThumbnailType) async -> Color? {
    let key = Self.key(id: id, type: type)
    if let cached = colors[key] { return cached }
    if let task = inFlight[key] { return await task.value }

    let task: Task<Color?, Never> = Task.detached {
      guard
        let url = try? await ThumbnailCache.shared.ensureThumbnail(id: id, type: type),
        let average = Self.averageColor(at: url)
      else { return nil }
      return Self.cardTint(from: average)
    }
    inFlight[key] = task
    let result = await task.value
    inFlight[key] = nil
    if let result {
      colors[key] = result
    }
    return result
  }

  func invalidate(id: String, type: ThumbnailType) {
    colors[Self.key(id: id, type: type)] = nil
  }

  private static func key(id: String, type: ThumbnailType) -> String {
    "\(type.rawValue)#\(id)"
  }

  private nonisolated static func averageColor(at url: URL) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }

    let size = 8
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    guard
      let context = CGContext(
        data: &pixels,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    var red = 0
    var green = 0
    var blue = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      red += Int(pixels[offset])
      green += Int(pixels[offset + 1])
      blue += Int(pixels[offset + 2])
    }
    let count = CGFloat(size * size * 255)
    return (CGFloat(red) / count, CGFloat(green) / count, CGFloat(blue) / count)
  }

  private nonisolated static func cardTint(
    from average: (red: CGFloat, green: CGFloat, blue: CGFloat)
  ) -> Color {
    let (red, green, blue) = average
    let maxComponent = max(red, green, blue)
    let minComponent = min(red, green, blue)
    let delta = maxComponent - minComponent

    var hue: CGFloat = 0
    if delta > 0 {
      switch maxComponent {
      case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
      case green: hue = (blue - red) / delta + 2
      default: hue = (red - green) / delta + 4
      }
      hue /= 6
    }
    let saturation = maxComponent == 0 ? 0 : delta / maxComponent

    return Color(
      hue: hue,
      saturation: min(saturation, 0.8),
      brightness: min(max(maxComponent, 0.2), 0.45)
    )
  }
}
