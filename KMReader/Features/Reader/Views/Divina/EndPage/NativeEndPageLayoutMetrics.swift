#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@MainActor
struct NativeEndPageLayoutMetrics {
  let badgeFont: PlatformFont
  let titleFont: PlatformFont
  let detailFont: PlatformFont
  let outerPadding: CGFloat
  let innerPadding: CGFloat
  let stackSpacing: CGFloat
  let portraitSectionSpacing: CGFloat
  let sectionContentMaxWidth: CGFloat
  let horizontalDividerWidth: CGFloat
  let coverWidth: CGFloat
  let coverHeight: CGFloat
  let dividerHeight: CGFloat

  static func resolve(for bounds: CGRect) -> NativeEndPageLayoutMetrics {
    let isPortrait = bounds.height >= bounds.width
    let minDimension = min(bounds.width, bounds.height)
    let maxDimension = max(bounds.width, bounds.height)
    let outerPadding = PlatformDefaults.outerPadding(minDimension: minDimension)
    let innerPadding = PlatformDefaults.innerPadding(minDimension: minDimension)
    let stackSpacing = PlatformDefaults.stackSpacing(minDimension: minDimension)
    let coverWidth = PlatformDefaults.coverWidth(minDimension: minDimension, isPortrait: isPortrait)

    return NativeEndPageLayoutMetrics(
      badgeFont: PlatformDefaults.badgeFont,
      titleFont: PlatformDefaults.titleFont,
      detailFont: PlatformDefaults.detailFont,
      outerPadding: outerPadding,
      innerPadding: innerPadding,
      stackSpacing: stackSpacing,
      portraitSectionSpacing: stackSpacing + clamped(stackSpacing * 0.5, lower: 6, upper: 12),
      sectionContentMaxWidth: PlatformDefaults.sectionContentMaxWidth(minDimension: minDimension),
      horizontalDividerWidth: clamped(bounds.width * 0.78, lower: 260, upper: 680),
      coverWidth: coverWidth,
      coverHeight: coverWidth / CoverAspectRatio.widthToHeight,
      dividerHeight: clamped(maxDimension * 0.32, lower: 140, upper: 320)
    )
  }

  #if os(iOS) || os(tvOS)
    static var coverHeightConstraintPriority: UILayoutPriority {
      #if os(tvOS)
        .defaultHigh
      #else
        .required
      #endif
    }

    static func protectVerticalText(_ label: UILabel) {
      #if os(tvOS)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
      #endif
    }

    static func allowCoverToYieldVerticalSpace(_ view: UIView) {
      #if os(tvOS)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
      #endif
    }
  #endif

  private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, lower), upper)
  }

  private enum PlatformDefaults {
    static var badgeFont: PlatformFont {
      #if os(tvOS)
        .preferredFont(forTextStyle: .caption2)
      #else
        preferredFont(textStyle: .caption1, weight: .semibold)
      #endif
    }

    static var titleFont: PlatformFont {
      #if os(tvOS)
        .preferredFont(forTextStyle: .headline)
      #else
        preferredFont(textStyle: .title3, design: .serif, weight: .bold)
      #endif
    }

    static var detailFont: PlatformFont {
      #if os(tvOS)
        .preferredFont(forTextStyle: .caption2)
      #else
        .preferredFont(forTextStyle: .caption1)
      #endif
    }

    static func outerPadding(minDimension: CGFloat) -> CGFloat {
      #if os(tvOS)
        clamped(minDimension * 0.045, lower: 20, upper: 40)
      #else
        clamped(minDimension * 0.08, lower: 20, upper: 56)
      #endif
    }

    static func innerPadding(minDimension: CGFloat) -> CGFloat {
      #if os(tvOS)
        clamped(minDimension * 0.028, lower: 14, upper: 22)
      #elseif os(iOS)
        clamped(minDimension * 0.045, lower: 16, upper: 32)
      #elseif os(macOS)
        0
      #endif
    }

    static func stackSpacing(minDimension: CGFloat) -> CGFloat {
      #if os(tvOS)
        clamped(minDimension * 0.022, lower: 10, upper: 16)
      #else
        clamped(minDimension * 0.034, lower: 12, upper: 22)
      #endif
    }

    static func sectionContentMaxWidth(minDimension: CGFloat) -> CGFloat {
      #if os(tvOS)
        clamped(minDimension * 0.48, lower: 420, upper: 560)
      #else
        clamped(minDimension * 0.72, lower: 280, upper: 420)
      #endif
    }

    static func coverWidth(minDimension: CGFloat, isPortrait: Bool) -> CGFloat {
      #if os(tvOS)
        clamped(minDimension * 0.18, lower: 100, upper: 150)
      #elseif os(iOS)
        clamped(minDimension * 0.24, lower: 96, upper: 190)
      #elseif os(macOS)
        clamped(minDimension * (isPortrait ? 0.28 : 0.22), lower: 96, upper: 190)
      #endif
    }

    #if os(iOS)
      private static func preferredFont(
        textStyle: UIFont.TextStyle,
        design: UIFontDescriptor.SystemDesign? = nil,
        weight: UIFont.Weight? = nil
      ) -> UIFont {
        var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        if let design, let designedDescriptor = descriptor.withDesign(design) {
          descriptor = designedDescriptor
        }
        if let weight {
          descriptor = descriptor.addingAttributes([
            UIFontDescriptor.AttributeName.traits: [UIFontDescriptor.TraitKey.weight: weight]
          ])
        }
        return UIFont(descriptor: descriptor, size: 0)
      }
    #elseif os(macOS)
      private static func preferredFont(
        textStyle: NSFont.TextStyle,
        design: NSFontDescriptor.SystemDesign? = nil,
        weight: NSFont.Weight? = nil
      ) -> NSFont {
        var descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: textStyle)
        if let design, let designedDescriptor = descriptor.withDesign(design) {
          descriptor = designedDescriptor
        }
        if let weight {
          descriptor = descriptor.addingAttributes([
            NSFontDescriptor.AttributeName.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
          ])
        }
        return NSFont(descriptor: descriptor, size: 0) ?? NSFont.preferredFont(forTextStyle: textStyle)
      }
    #endif
  }
}
