#if os(iOS)
  import SwiftUI

  extension ScrollPageView {
    func panelModeLongPress(
      action: @escaping (PanelEngagementPoint?) -> Void,
      onTouchDown: @escaping (PanelEngagementPoint?) -> Void,
      onLongPressBegan: @escaping (PanelEngagementPoint?) -> Void,
      onWarmup: @escaping () -> Void,
      onWarmupCancel: @escaping () -> Void
    ) -> ScrollPageView {
      ScrollPageView(
        mode: mode,
        viewportSize: viewportSize,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode,
        navigationAnimationDuration: navigationAnimationDuration,
        renderConfig: renderConfig,
        viewModel: viewModel,
        readListContext: readListContext,
        onDismiss: onDismiss,
        onTapZoneTap: onTapZoneTap,
        onPanelLongPress: action,
        onPanelTouchDown: onTouchDown,
        onPanelLongPressBegan: onLongPressBegan,
        onPanelWarmup: onWarmup,
        onPanelWarmupCancel: onWarmupCancel
      )
    }
  }
#endif
