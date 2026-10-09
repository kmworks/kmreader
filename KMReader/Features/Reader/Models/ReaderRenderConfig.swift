//
// ReaderRenderConfig.swift
//
//

import Foundation

struct ReaderRenderConfig: Equatable {
  let tapZoneMode: TapZoneMode
  let tapZoneInversionMode: TapZoneInversionMode
  let showPageNumber: Bool
  let showPageShadow: Bool
  let readerBackground: ReaderBackground
  let enableLiveText: Bool
  let enableImageContextMenu: Bool
  let supportsPageSoloActions: Bool
  let doubleTapZoomScale: Double
  let doubleTapZoomMode: DoubleTapZoomMode
}
