//
// ReaderViewItemGenerator.swift
//
//

import Foundation

struct ReaderViewItemGenerator {
  static func generate(
    segments: [ReaderSegment],
    readerPages: [ReaderPage],
    noCover: Bool,
    allowDualPairs: Bool,
    forceDualPairs: Bool,
    splitWidePages: Bool,
    keepsSplitSpreadsWhole: Bool,
    pageCurl: Bool,
    soloPages: Set<Int> = [],
    rotation: ReaderRotation = .none
  ) -> (items: [ReaderViewItem], indexByPage: [ReaderPageID: Int]) {
    let items = generateViewItems(
      segments: segments,
      readerPages: readerPages,
      noCover: noCover,
      allowDualPairs: allowDualPairs,
      forceDualPairs: forceDualPairs,
      splitWidePages: splitWidePages,
      keepsSplitSpreadsWhole: keepsSplitSpreadsWhole,
      pageCurl: pageCurl,
      soloPages: soloPages,
      rotation: rotation
    )
    return (items, generateViewItemIndexMap(items: items))
  }

  private static func generateViewItems(
    segments: [ReaderSegment],
    readerPages: [ReaderPage],
    noCover: Bool,
    allowDualPairs: Bool,
    forceDualPairs: Bool,
    splitWidePages: Bool,
    keepsSplitSpreadsWhole: Bool,
    pageCurl: Bool,
    soloPages: Set<Int> = [],
    rotation: ReaderRotation = .none
  ) -> [ReaderViewItem] {
    guard !segments.isEmpty, !readerPages.isEmpty else { return [] }

    enum PageOrientation {
      case portrait
      case landscape
      case unknown

      var isKnownLandscape: Bool {
        self == .landscape
      }

      var isPairableInForcedDual: Bool {
        self != .landscape
      }
    }

    func effectiveOrientation(at index: Int) -> PageOrientation {
      let page = readerPages[index].page
      guard let width = page.width, let height = page.height else { return .unknown }
      let size = rotation.rotatedSize(
        CGSize(width: CGFloat(width), height: CGFloat(height))
      )
      return size.height > size.width ? .portrait : .landscape
    }

    var items: [ReaderViewItem] = []
    let shouldForceDualPairs = allowDualPairs && forceDualPairs

    var segmentStartIndex = 0
    for segment in segments {
      let segmentPageCount = segment.pages.count
      guard segmentPageCount > 0 else {
        continue
      }

      let segmentEndExclusive = segmentStartIndex + segmentPageCount
      var index = segmentStartIndex

      while index < segmentEndExclusive {
        if shouldForceDualPairs {
          let currentOrientation = effectiveOrientation(at: index)
          let isCoverPage = !noCover && index == segmentStartIndex
          let isWideCoverPage = isCoverPage && currentOrientation.isKnownLandscape
          let isWidePageEligibleForSplit =
            (splitWidePages || pageCurl)
            && currentOrientation.isKnownLandscape
            && (noCover || isWideCoverPage || index != segmentStartIndex)

          if isWidePageEligibleForSplit {
            items.append(.split(id: readerPages[index].id, part: .both))
            index += 1
            continue
          }

          if currentOrientation.isKnownLandscape && !pageCurl {
            items.append(.page(id: readerPages[index].id))
            index += 1
            continue
          }

          let nextIsPairable =
            index + 1 < segmentEndExclusive
            ? effectiveOrientation(at: index + 1).isPairableInForcedDual
            : true
          let shouldShowSingle =
            (isCoverPage && currentOrientation.isPairableInForcedDual) || index == segmentEndExclusive - 1
            || soloPages.contains(index) || soloPages.contains(index + 1)
            || !nextIsPairable  // next page is wide → keep it for its own item
          if shouldShowSingle {
            items.append(.page(id: readerPages[index].id))
            index += 1
          } else {
            let nextIndex = index + 1
            items.append(.dual(first: readerPages[index].id, second: readerPages[nextIndex].id))
            index += 2
          }
          continue
        }

        let currentOrientation = effectiveOrientation(at: index)
        let currentIsPortrait = currentOrientation == .portrait

        var useSinglePage = false
        var shouldSplitPage = false

        let isCoverPage = !noCover && index == segmentStartIndex
        let isWideCoverPage = isCoverPage && !currentIsPortrait

        // Wide pages split only when enabled. In dual-page mode that produces a two-slot
        // spread; in single-page presentation, one whole spread that pans, or two
        // half items where the platform pages through the halves.
        let isWidePageEligibleForSplit =
          (splitWidePages || (pageCurl && allowDualPairs))
          && !currentIsPortrait
          && (noCover || isWideCoverPage || index != segmentStartIndex)

        if isWidePageEligibleForSplit {
          shouldSplitPage = true
        }

        // Determine if page should be shown as single (without splitting)
        if !currentIsPortrait && !shouldSplitPage {
          useSinglePage = true
        }
        if isCoverPage && !isWideCoverPage {
          useSinglePage = true
        }
        if soloPages.contains(index) {
          useSinglePage = true
        }
        if index == segmentEndExclusive - 1 {
          useSinglePage = true
        }

        if shouldSplitPage {
          if allowDualPairs || keepsSplitSpreadsWhole {
            items.append(.split(id: readerPages[index].id, part: .both))
          } else {
            items.append(.split(id: readerPages[index].id, part: .first))
            items.append(.split(id: readerPages[index].id, part: .second))
          }
          index += 1
        } else if useSinglePage {
          items.append(.page(id: readerPages[index].id))
          index += 1
        } else {
          let nextIsPortrait = effectiveOrientation(at: index + 1) == .portrait
          if allowDualPairs && index + 1 < segmentEndExclusive
            && nextIsPortrait
            && !soloPages.contains(index + 1)
          {
            items.append(.dual(first: readerPages[index].id, second: readerPages[index + 1].id))
            index += 2
          } else {
            items.append(.page(id: readerPages[index].id))
            index += 1
          }
        }
      }

      items.append(
        .end(id: readerPages[segmentEndExclusive - 1].id)
      )
      segmentStartIndex = segmentEndExclusive
    }

    return items
  }

  private static func generateViewItemIndexMap(items: [ReaderViewItem]) -> [ReaderPageID: Int] {
    var indices: [ReaderPageID: Int] = [:]
    for (index, item) in items.enumerated() {
      switch item {
      case .dual(let first, let second):
        if indices[first] == nil {
          indices[first] = index
        }
        if indices[second] == nil {
          indices[second] = index
        }
      default:
        let pageID = item.pageID
        if indices[pageID] == nil {
          indices[pageID] = index
        }
      }
    }
    return indices
  }
}
