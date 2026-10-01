//
// LayoutConfig.swift
//
//

import Foundation
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Layout configuration helper for platform-specific card sizes.
/// Card sizes are fixed per platform (calibrated against Apple Books);
/// there is no user-adjustable density.
struct LayoutConfig {

  /// Measured content width where detail pages switch between the centered
  /// narrow header and the leading wide one (series/read list/collection:
  /// the two-column layout).
  static let detailWideLayoutMinimumWidth: CGFloat = 960

  /// Card width for the medium browse grid (library/series/books/read
  /// lists/collections): one notch below the large grid. The iOS value is
  /// calibrated so any full-size iPhone (>=390pt) fits 3 columns (3x108 +
  /// 2x16 spacing within the 358pt content width) where the large grid
  /// fits 2.
  static var gridCardWidth: CGFloat {
    #if os(tvOS)
      return 190
    #elseif os(macOS)
      // Apple Books macOS covers are ~104pt; the medium grid sits in that
      // density band instead of scaling up from iPhone.
      return 104
    #else
      return 108
    #endif
  }

  /// Card width for the large-grid browse layout. Takes over the original
  /// single-grid size, which reads as the large density in practice.
  static var largeGridCardWidth: CGFloat {
    #if os(tvOS)
      return 240
    #elseif os(macOS)
      return 128
    #else
      return 160
    #endif
  }

  /// Large dashboard card width (showcase sections, e.g. recently added books).
  static var dashboardLargeCardWidth: CGFloat {
    #if os(tvOS)
      return 365
    #elseif os(macOS)
      // Apple Books macOS showcase covers are ~104pt; the large card adds
      // text lines below the cover, so it stays a bit wider than the small
      // card (101) instead of using the iOS 2.1x ratio.
      return 132
    #else
      // Apple Books showcase covers are ~150pt on both iPhone and iPad.
      return 152
    #endif
  }

  /// Medium dashboard card width, midway between the large showcase and the
  /// small utility cards.
  static var dashboardMediumCardWidth: CGFloat {
    #if os(tvOS)
      return 270
    #elseif os(macOS)
      return 116
    #else
      if UIDevice.current.userInterfaceIdiom == .pad {
        return 124
      } else {
        return 116
      }
    #endif
  }

  /// Small dashboard card width (utility sections, e.g. on deck, series).
  static var dashboardSmallCardWidth: CGFloat {
    #if os(tvOS)
      return 190
    #elseif os(macOS)
      return 100
    #else
      if UIDevice.current.userInterfaceIdiom == .pad {
        return 96
      } else {
        return 80
      }
    #endif
  }

  /// Width of horizontal cards (dashboard book sections, pinned read lists/collections).
  /// iOS/tvOS span three small-card widths so the strip stays balanced next to
  /// small cards while matching Apple Books' Reading Now length; macOS keeps
  /// its denser band at 2.5x.
  static var horizontalCardWidth: CGFloat {
    #if os(tvOS)
      return 570
    #elseif os(macOS)
      return 250
    #else
      if UIDevice.current.userInterfaceIdiom == .pad {
        return 288
      } else {
        return 240
      }
    #endif
  }

  /// Cover width inside horizontal cards. The cover is about as tall as the
  /// text column it sits next to (two-line title + series line + bottom bar ≈
  /// 4 lines + 4pt spacing), so the card is no taller than its text.
  static var horizontalCoverWidth: CGFloat {
    #if os(tvOS)
      return 99
    #elseif os(macOS)
      return 45
    #else
      if UIDevice.current.userInterfaceIdiom == .pad {
        return 56
      } else {
        return 45
      }
    #endif
  }

  /// Text styles rendered below a grid-style card cover, scaled to the card
  /// width. `title` is the book/series name, `secondary` the series/progress
  /// lines, `tertiary` the small accessory icons.
  struct CardTextStyle {
    let title: Font.TextStyle
    let secondary: Font.TextStyle
    let tertiary: Font.TextStyle
  }

  /// Width below which a card uses the smaller text tier. Sits between the
  /// dashboard medium and large card widths so the large card (and the large
  /// browse grid) reads a notch larger than the medium/small cards.
  private static var cardLargeTextMinimumWidth: CGFloat {
    #if os(tvOS)
      return 300
    #elseif os(macOS)
      return 124
    #else
      return 130
    #endif
  }

  static func cardTextStyle(cardWidth: CGFloat) -> CardTextStyle {
    let large = cardWidth >= cardLargeTextMinimumWidth
    return CardTextStyle(
      title: large ? .callout : .subheadline,
      secondary: large ? .footnote : .caption,
      tertiary: large ? .caption : .caption2
    )
  }

  /// Font size (pt) for the title line of horizontal cards (semibold, Apple
  /// Books style); the series and meta lines step down from it. Fixed pt
  /// instead of a text style keeps the text column height directly computable
  /// for `horizontalCoverWidth` (4 lines ≈ 5.2x the size, +4pt spacing).
  static var horizontalCardFontSize: CGFloat {
    #if os(tvOS)
      return 28
    #elseif os(macOS)
      return 13
    #else
      if UIDevice.current.userInterfaceIdiom == .pad {
        return 16
      } else {
        return 13
      }
    #endif
  }

  /// Font size (pt) for the series line of horizontal cards. Apple Books
  /// steps secondary lines down further than a 1pt decrement (author ≈ 0.8x
  /// the title), so the series/meta lines sit visibly below the title.
  static var horizontalCardSeriesFontSize: CGFloat {
    horizontalCardFontSize - 2
  }

  /// Font size (pt) for the meta (bottom bar) line of horizontal cards.
  static var horizontalCardMetaFontSize: CGFloat {
    horizontalCardFontSize - 3
  }

  /// Icon size (pt) for the trailing accessory icons in horizontal cards.
  static var horizontalCardAccessoryIconSize: CGFloat {
    #if os(tvOS)
      return 30
    #elseif os(macOS)
      return 14
    #else
      if UIDevice.current.userInterfaceIdiom == .pad {
        return 16
      } else {
        return 15
      }
    #endif
  }

  /// Corner badge (unread count/indicator) size on card covers. Scales with
  /// the card width so wide cards get a larger badge; the floor keeps digits
  /// legible on the smallest dashboard cards.
  static func cardBadgeSize(cardWidth: CGFloat) -> CGFloat {
    #if os(tvOS)
      return max(UnreadCountBadge.defaultSize, (cardWidth * 0.1).rounded())
    #else
      return max(9, (cardWidth * 0.1).rounded())
    #endif
  }

  /// Vertical padding inside a dashboard section band, above the header and
  /// below the card strip. Both ends are equal so content sits evenly between
  /// the band's gradient edges (Apple Books style); adjacent bands touch, so
  /// each band's gray gradient edge is the separator between sections.
  static var dashboardSectionVerticalPadding: CGFloat {
    #if os(tvOS)
      return 40
    #else
      return 30
    #endif
  }

  /// Band padding when the gradient background is off: without a visible band
  /// edge the full padding reads as empty space between sections, so the gap
  /// shrinks to twice the header-to-cards spacing.
  static var dashboardSectionVerticalPaddingCompact: CGFloat {
    #if os(tvOS)
      return 24
    #else
      return 16
    #endif
  }

  /// Spacing between a dashboard section header and its card strip. Tighter
  /// than the band padding so the header groups with its cards.
  static var dashboardSectionHeaderSpacing: CGFloat {
    #if os(tvOS)
      return 24
    #else
      return 16
    #endif
  }

  /// Default spacing between cards
  static var defaultSpacing: CGFloat {
    #if os(tvOS)
      return 40
    #elseif os(macOS)
      return 24
    #else
      return 16
    #endif
  }

  /// Adaptive grid columns based on the given card width
  static func adaptiveColumns(cardWidth: CGFloat = gridCardWidth) -> [GridItem] {
    [GridItem(.adaptive(minimum: cardWidth, maximum: .infinity), spacing: defaultSpacing)]
  }
}
