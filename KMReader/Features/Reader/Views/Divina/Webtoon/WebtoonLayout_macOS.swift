//
// WebtoonLayout_macOS.swift
//
//

#if os(macOS)
  import AppKit

  class WebtoonLayout: NSCollectionViewFlowLayout {
    override func prepare() {
      super.prepare()
      scrollDirection = .vertical
      minimumLineSpacing = 0
      minimumInteritemSpacing = 0
      sectionInset = NSEdgeInsetsZero
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
      guard let collectionView = collectionView else { return true }
      return collectionView.bounds.size != newBounds.size
    }
  }
#endif
