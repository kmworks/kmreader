#if os(iOS)
  import SwiftUI

  extension ScrollPageView {
    func panelModeLongPress(
      action: @escaping (PanelEngagementPoint?) -> Void,
      controller: PanelModeController
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
        panelModeController: controller
      )
    }
  }
#endif
