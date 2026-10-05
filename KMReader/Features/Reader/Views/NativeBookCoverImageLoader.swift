//
// NativeBookCoverImageLoader.swift
//
//

import Foundation

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

func loadNativeBookCoverImage(for bookID: String) async -> PlatformImage? {
  await ThumbnailCache.shared.image(id: bookID, type: .book)
}
