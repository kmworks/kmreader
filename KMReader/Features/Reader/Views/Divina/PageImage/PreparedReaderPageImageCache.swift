//
// PreparedReaderPageImageCache.swift
//

import Foundation

@MainActor
final class PreparedReaderPageImageCache {
  private var sourceImage: PlatformImage?
  private var rotation: ReaderRotation = .none
  private var splitMode: PageSplitMode = .none
  private var borderCropMode: ReaderPageBorderCropMode = .disabled
  private var preparedImage: PlatformImage?

  func resolve(
    sourceImage: PlatformImage,
    rotation: ReaderRotation,
    splitMode: PageSplitMode,
    borderCropMode: ReaderPageBorderCropMode,
    prepare: () -> PlatformImage?
  ) -> PlatformImage? {
    if self.sourceImage === sourceImage,
      self.rotation == rotation,
      self.splitMode == splitMode,
      self.borderCropMode == borderCropMode
    {
      return preparedImage
    }

    let preparedImage = prepare()
    self.sourceImage = sourceImage
    self.rotation = rotation
    self.splitMode = splitMode
    self.borderCropMode = borderCropMode
    self.preparedImage = preparedImage
    return preparedImage
  }

  func clear() {
    sourceImage = nil
    preparedImage = nil
  }
}
