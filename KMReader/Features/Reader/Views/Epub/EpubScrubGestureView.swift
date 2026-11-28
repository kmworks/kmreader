//
// EpubScrubGestureView.swift
//
//

#if os(iOS)
  import SwiftUI

  /// Bridges `EpubScrubGestureUIView` into SwiftUI, resolving the scrub preview
  /// at each touch position in the container's full-width coordinate space.
  struct EpubScrubGestureView: UIViewRepresentable {
    let restingTrackWidth: CGFloat
    let isScrubbing: Bool
    let interfaceStyle: UIUserInterfaceStyle
    let previewAtPoint: (CGFloat) -> EpubScrubPreview?
    let onBegan: (EpubScrubPreview) -> Void
    let onChanged: (EpubScrubPreview) -> Void
    let onEnded: (EpubScrubPreview?) -> Void
    let onCancelled: () -> Void

    func makeUIView(context: Context) -> EpubScrubGestureUIView {
      EpubScrubGestureUIView()
    }

    func updateUIView(_ uiView: EpubScrubGestureUIView, context: Context) {
      if !isScrubbing {
        uiView.cancelActiveScrub()
      }
      uiView.restingTrackWidth = restingTrackWidth
      uiView.isScrubbing = isScrubbing
      uiView.interfaceStyle = interfaceStyle
      uiView.previewAtPoint = previewAtPoint
      uiView.onBegan = onBegan
      uiView.onChanged = onChanged
      uiView.onEnded = onEnded
      uiView.onCancelled = onCancelled
    }

    static func dismantleUIView(_ uiView: EpubScrubGestureUIView, coordinator: ()) {
      uiView.cancelActiveScrub()
    }
  }
#endif
