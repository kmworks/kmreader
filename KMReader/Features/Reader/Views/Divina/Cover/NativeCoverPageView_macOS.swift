#if os(macOS)
  import AppKit
  import SwiftUI

  struct NativeCoverPageView: NSViewRepresentable {
    struct SlotRenderState {
      let isVisible: Bool
      let isMoving: Bool
      let isElevated: Bool
      let isActive: Bool
      let zIndex: Double

      static let hidden = SlotRenderState(
        isVisible: false,
        isMoving: false,
        isElevated: false,
        isActive: false,
        zIndex: -1
      )
    }

    enum TransitionMetrics {
      static let minimumDragDistance: CGFloat = 1
      static let directionalDragBias: CGFloat = 4
      static let overscrollResistance: CGFloat = 0.2
      static let cancelThreshold: CGFloat = 0.5
      static let commitDistanceRatio: CGFloat = 0.18
      static let commitVelocityThreshold: CGFloat = 700
      static let gestureAnimationDuration: Double = 0.3
      static let movingShadowOpacity: Double = 0.12
      static let idleShadowOpacity: Double = 0.05
      static let movingShadowRadius: CGFloat = 5
      static let idleShadowRadius: CGFloat = 2
      static let movingShadowOffset: CGFloat = 3
      static let idleShadowOffset: CGFloat = 1
    }

    let mode: PageViewMode
    let readingDirection: ReadingDirection
    let splitWidePageMode: SplitWidePageMode
    let tapNavigationAnimationDuration: Double
    let renderConfig: ReaderRenderConfig
    @Bindable var viewModel: ReaderViewModel
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler

    func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }

    func makeNSView(context: Context) -> NativeCoverContainerView {
      let containerView = NativeCoverContainerView()
      containerView.onDidLayout = { [weak coordinator = context.coordinator] in
        coordinator?.handleContainerLayout()
      }
      context.coordinator.attach(to: containerView)
      context.coordinator.update(from: self)
      return containerView
    }

    func updateNSView(_ nsView: NativeCoverContainerView, context: Context) {
      context.coordinator.attach(to: nsView)
      context.coordinator.update(from: self)
    }

    static func dismantleNSView(_ nsView: NativeCoverContainerView, coordinator: Coordinator) {
      coordinator.teardown()
      nsView.prepareForDismantle()
    }
  }
#endif
