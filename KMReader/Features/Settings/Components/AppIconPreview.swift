//
// AppIconPreview.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Renders an icon option the way the home screen shows it: the .icon
  /// bundle's background fill with the glyph image, which maps 1:1 onto the
  /// icon canvas.
  struct AppIconPreview: View {
    let option: AppIconOption
    var size: CGFloat

    /// Continuous corner radius approximating the system's icon mask.
    static func cornerRadius(for size: CGFloat) -> CGFloat {
      size * 0.2237
    }

    private var cornerRadius: CGFloat {
      Self.cornerRadius(for: size)
    }

    var body: some View {
      ZStack {
        background
        Image(option.logoAssetName)
          .resizable()
          .aspectRatio(contentMode: .fit)
      }
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
      )
    }

    @ViewBuilder
    private var background: some View {
      switch option {
      case .primary:
        Color.appIconBackgroundPrimary
      case .classic:
        LinearGradient(
          colors: [.appIconBackgroundClassicTop, .appIconBackgroundClassicBottom],
          startPoint: .top,
          endPoint: UnitPoint(x: 0.5, y: 0.7)
        )
      case .legacy:
        Color.white
      }
    }
  }
#endif
