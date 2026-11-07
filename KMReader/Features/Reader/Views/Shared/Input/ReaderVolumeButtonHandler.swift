import SwiftUI

#if os(iOS)
  import UIKit

  struct ReaderVolumeButtonHandler: UIViewRepresentable {
    let isEnabled: Bool
    let onVolumeUp: () -> Void
    let onVolumeDown: () -> Void

    func makeUIView(context: Context) -> ReaderVolumeButtonHandlerView {
      let view = ReaderVolumeButtonHandlerView()
      view.onVolumeUp = onVolumeUp
      view.onVolumeDown = onVolumeDown
      view.isCaptureEnabled = isEnabled
      return view
    }

    func updateUIView(_ uiView: ReaderVolumeButtonHandlerView, context: Context) {
      uiView.onVolumeUp = onVolumeUp
      uiView.onVolumeDown = onVolumeDown
      uiView.isCaptureEnabled = isEnabled
    }
  }
#endif
