//
// WebtoonPageView.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  struct WebtoonPageView: View {
    let viewModel: ReaderViewModel
    let readListContext: ReaderReadListContext?
    let onDismiss: () -> Void
    let onTapZoneTap: ReaderTapZoneTapHandler
    let scrollController: WebtoonScrollController
    let pageWidthPercentage: Double
    let renderConfig: ReaderRenderConfig
    @State private var zoomTargetPageID: ReaderPageID?
    @State private var zoomAnchor: CGPoint?
    @State private var zoomRequestID: UUID?

    func pageWidth(_ geometry: GeometryProxy) -> CGFloat {
      return geometry.size.width * (pageWidthPercentage / 100.0)
    }

    var body: some View {
      GeometryReader { geometry in
        ZStack {
          WebtoonReaderView(
            viewModel: viewModel,
            pageWidth: pageWidth(geometry),
            renderConfig: renderConfig,
            readListContext: readListContext,
            onDismiss: onDismiss,
            onTapZoneTap: onTapZoneTap,
            onZoomRequest: { pageID, anchor in
              openZoomOverlay(pageID: pageID, anchor: anchor)
            },
            scrollController: scrollController
          )

          if let zoomTargetPageID, let zoomRequestID {
            WebtoonZoomOverlayView(
              viewModel: viewModel,
              pageID: zoomTargetPageID,
              zoomAnchor: zoomAnchor,
              zoomRequestID: zoomRequestID,
              renderConfig: renderConfig,
              onClose: {
                viewModel.isZoomed = false
                withAnimation(.appCurve(0.2)) {
                  self.zoomTargetPageID = nil
                  self.zoomAnchor = nil
                  self.zoomRequestID = nil
                }
              }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .zIndex(2)
          }
        }
      }
    }

    private func openZoomOverlay(pageID: ReaderPageID, anchor: CGPoint) {
      guard zoomTargetPageID == nil else { return }
      guard viewModel.page(for: pageID) != nil else { return }

      withAnimation(.appCurve(0.2)) {
        zoomTargetPageID = pageID
        zoomAnchor = anchor
        zoomRequestID = UUID()
      }
      if viewModel.preloadedImage(for: pageID) == nil {
        Task {
          await viewModel.preloadImage(for: pageID)
        }
      }
    }
  }
#endif
