//
// WebtoonZoomOverlayView.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  struct WebtoonZoomOverlayView: View {
    @Bindable var viewModel: ReaderViewModel
    let pageID: ReaderPageID
    let zoomAnchor: CGPoint?
    let zoomRequestID: UUID
    let renderConfig: ReaderRenderConfig
    let onClose: () -> Void

    @State private var hasZoomedIn = false

    private var zoomRenderConfig: ReaderRenderConfig {
      ReaderRenderConfig(
        tapZoneMode: .none,
        tapZoneInversionMode: renderConfig.tapZoneInversionMode,
        showPageNumber: renderConfig.showPageNumber,
        showPageShadow: renderConfig.showPageShadow,
        readerBackground: renderConfig.readerBackground,
        enableLiveText: renderConfig.enableLiveText,
        enableImageContextMenu: renderConfig.enableImageContextMenu,
        supportsPageSoloActions: false,
        doubleTapZoomScale: renderConfig.doubleTapZoomScale,
        doubleTapZoomMode: renderConfig.doubleTapZoomMode
      )
    }

    var body: some View {
      GeometryReader { geometry in
        let initialScale = CGFloat(zoomRenderConfig.doubleTapZoomScale)

        if viewModel.page(for: pageID) != nil {
          PageScrollView(
            viewModel: viewModel,
            screenSize: geometry.size,
            resetID: zoomRequestID,
            minScale: 1.0,
            maxScale: 8.0,
            displayMode: .fillWidth,
            readingDirection: .webtoon,
            renderConfig: zoomRenderConfig,
            initialZoomScale: initialScale,
            initialZoomAnchor: zoomAnchor,
            initialZoomID: zoomRequestID,
            pages: [
              NativePageData(
                pageID: pageID,
                isLoading: viewModel.isLoading && viewModel.preloadedImage(for: pageID) == nil,
                alignment: .center
              )
            ]
          )
        }
      }
      .background(renderConfig.readerBackground.color.readerIgnoresSafeArea())
      .readerIgnoresSafeArea()
      .onChange(of: viewModel.isZoomed) { _, isZoomed in
        if isZoomed {
          hasZoomedIn = true
        } else if hasZoomedIn {
          onClose()
        }
      }
    }
  }
#endif
