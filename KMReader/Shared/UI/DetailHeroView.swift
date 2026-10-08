//
// DetailHeroView.swift
//
//

import SwiftUI

private struct DetailHeroCenteredKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Set by detail page content views so the hero and the action-card zone
  /// share one alignment: centered below the detail wide-layout minimum
  /// width, leading above it. Wide two-column rails inject `true` for their
  /// centered rail content.
  var detailHeroCentered: Bool {
    get { self[DetailHeroCenteredKey.self] }
    set { self[DetailHeroCenteredKey.self] = newValue }
  }
}

/// Detail page hero: cover plus an info block. Centered mode stacks a large
/// cover above the centered info block; otherwise the cover sits beside the
/// leading info block at `PlatformHelper.detailThumbnailWidth`.
struct DetailHeroView<Info: View>: View {
  let id: String
  let type: ThumbnailType
  let contentBlurRadius: CGFloat
  @ViewBuilder let info: Info

  @Environment(\.detailHeroCentered) private var isCentered

  init(
    id: String,
    type: ThumbnailType,
    contentBlurRadius: CGFloat,
    @ViewBuilder info: () -> Info
  ) {
    self.id = id
    self.type = type
    self.contentBlurRadius = contentBlurRadius
    self.info = info()
  }

  var body: some View {
    if isCentered {
      VStack(spacing: 16) {
        DetailCoverView(
          id: id,
          type: type,
          contentBlurRadius: contentBlurRadius,
          width: LayoutConfig.detailHeroCoverWidth
        )
        info
          .frame(maxWidth: .infinity)
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        DetailCoverView(
          id: id,
          type: type,
          contentBlurRadius: contentBlurRadius,
          width: PlatformHelper.detailThumbnailWidth
        )
        info
      }
    }
  }
}
