import SwiftUI

extension ReaderViewModel {
  func nativePageData(
    for item: ReaderViewItem,
    readingDirection: ReadingDirection,
    splitWidePageMode: SplitWidePageMode,
    isPlaybackActive: Bool
  ) -> [NativePageData] {
    switch item {
    case .page(let id):
      return [makeNativePageData(for: id, alignment: .center, isPlaybackActive: isPlaybackActive)]
    case .split(let id, let part):
      if part == .both {
        return splitPairNativePageData(
          for: id,
          readingDirection: readingDirection,
          splitWidePageMode: splitWidePageMode,
          isPlaybackActive: isPlaybackActive
        )
      }
      return [
        makeNativePageData(
          for: id,
          alignment: part == .first ? .trailing : .leading,
          splitMode: nativeSplitMode(
            for: part,
            readingDirection: readingDirection,
            splitWidePageMode: splitWidePageMode
          ),
          isPlaybackActive: isPlaybackActive
        )
      ]
    case .dual(let first, let second):
      return [
        makeNativePageData(
          for: first,
          alignment: .trailing,
          isPlaybackActive: isPlaybackActive
        ),
        makeNativePageData(
          for: second,
          alignment: .leading,
          isPlaybackActive: isPlaybackActive
        ),
      ]
    case .end:
      return []
    }
  }

  /// Whole-spread presentation of `item` in a single-page engine, or nil when
  /// `item` is not a merged split. `currentItem` is the item the engine shows
  /// as current, which decides the edge an arriving spread opens at.
  func wholeSpreadPresentation(
    for item: ReaderViewItem,
    isDualPagePresentation: Bool,
    readingDirection: ReadingDirection,
    splitWidePageMode: SplitWidePageMode,
    relativeTo currentItem: ReaderViewItem?
  ) -> WholeSpreadPresentation? {
    guard !isDualPagePresentation, case .split(let pageID, .both) = item else { return nil }
    return WholeSpreadPresentation(
      pageID: pageID,
      startsAtLeft: isLeftSplitHalf(
        part: .first,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode
      ),
      arrivalEdge: wholeSpreadArrivalEdge(for: item, relativeTo: currentItem)
    )
  }

  private func splitPairNativePageData(
    for pageID: ReaderPageID,
    readingDirection: ReadingDirection,
    splitWidePageMode: SplitWidePageMode,
    isPlaybackActive: Bool
  ) -> [NativePageData] {
    let firstMode = nativeSplitMode(
      for: .first,
      readingDirection: readingDirection,
      splitWidePageMode: splitWidePageMode
    )
    let secondMode = nativeSplitMode(
      for: .second,
      readingDirection: readingDirection,
      splitWidePageMode: splitWidePageMode
    )

    return [
      makeNativePageData(
        for: pageID,
        alignment: .trailing,
        splitMode: firstMode,
        isPlaybackActive: isPlaybackActive
      ),
      makeNativePageData(
        for: pageID,
        alignment: .leading,
        splitMode: secondMode,
        isPlaybackActive: isPlaybackActive
      ),
    ]
  }

  private func nativeSplitMode(
    for part: ReaderSplitPart,
    readingDirection: ReadingDirection,
    splitWidePageMode: SplitWidePageMode
  ) -> PageSplitMode {
    let isLeftHalf = isLeftSplitHalf(
      part: part,
      readingDirection: readingDirection,
      splitWidePageMode: splitWidePageMode
    )
    return isLeftHalf ? .leftHalf : .rightHalf
  }

  private func makeNativePageData(
    for pageID: ReaderPageID,
    alignment: HorizontalAlignment,
    splitMode: PageSplitMode = .none,
    isPlaybackActive: Bool
  ) -> NativePageData {
    NativePageData(
      pageID: pageID,
      isLoading: page(for: pageID) != nil && preloadedImage(for: pageID) == nil
        && !hasFailedImageLoad(for: pageID),
      failure: imageLoadFailure(for: pageID),
      alignment: alignment,
      splitMode: splitMode,
      rotation: rotation,
      animatedSourceFileURL:
        isPlaybackActive && rotation == .none
        ? animatedSourceFileURL(for: pageID) : nil
    )
  }
}
