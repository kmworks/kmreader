import CoreGraphics
import CoreImage
import Foundation

nonisolated struct PreparedReaderPageGeometry {
  static func cropRect(
    for image: CGImage,
    rotation: ReaderRotation,
    borderCropMode: ReaderPageBorderCropMode
  ) -> CGRect? {
    guard borderCropMode != .disabled else { return nil }
    let orientation: Int32
    switch rotation {
    case .none:
      return ReaderPageBorderCropper.cropRect(for: image, mode: borderCropMode)
    case .degrees90:
      orientation = 6
    case .degrees180:
      orientation = 3
    case .degrees270:
      orientation = 8
    }
    let rotated = CIImage(cgImage: image).oriented(forExifOrientation: orientation)
    guard let rotatedImage = CIContext().createCGImage(rotated, from: rotated.extent) else { return nil }
    return ReaderPageBorderCropper.cropRect(for: rotatedImage, mode: borderCropMode)
  }

  static func normalizedRect(
    for sourceRect: CGRect,
    in image: CGImage,
    splitMode: PageSplitMode,
    rotation: ReaderRotation,
    cropRect: CGRect?
  ) -> CGRect {
    var rect = sourceRect
    switch rotation {
    case .none:
      break
    case .degrees90:
      rect = CGRect(x: 1 - rect.minY - rect.height, y: rect.minX, width: rect.height, height: rect.width)
    case .degrees180:
      rect = CGRect(
        x: 1 - rect.minX - rect.width, y: 1 - rect.minY - rect.height, width: rect.width, height: rect.height)
    case .degrees270:
      rect = CGRect(x: rect.minY, y: 1 - rect.minX - rect.width, width: rect.height, height: rect.width)
    }

    if let cropRect {
      let imageSize = rotation.rotatedSize(CGSize(width: image.width, height: image.height))
      let rotatedPixels = CGRect(
        x: rect.minX * imageSize.width,
        y: rect.minY * imageSize.height,
        width: rect.width * imageSize.width,
        height: rect.height * imageSize.height
      )
      let visiblePixels = rotatedPixels.intersection(cropRect)
      guard !visiblePixels.isNull else { return .zero }
      rect = CGRect(
        x: (visiblePixels.minX - cropRect.minX) / cropRect.width,
        y: (visiblePixels.minY - cropRect.minY) / cropRect.height,
        width: visiblePixels.width / cropRect.width,
        height: visiblePixels.height / cropRect.height
      )
    }

    switch splitMode {
    case .none:
      break
    case .leftHalf:
      rect = CGRect(x: rect.minX * 2, y: rect.minY, width: rect.width * 2, height: rect.height)
    case .rightHalf:
      rect = CGRect(
        x: rect.minX * 2 - 1,
        y: rect.minY,
        width: rect.width * 2,
        height: rect.height
      )
    }
    let clampedRect = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !clampedRect.isNull else { return .zero }
    return clampedRect
  }

  static func isVisible(_ rect: CGRect) -> Bool {
    rect.width > 0 && rect.height > 0 && rect.intersects(CGRect(x: 0, y: 0, width: 1, height: 1))
  }
}
