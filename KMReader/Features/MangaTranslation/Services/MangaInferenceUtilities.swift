import CoreGraphics
import CoreImage
import CoreML
import Foundation

nonisolated enum MangaInferenceUtilities {
  static func prediction(_ model: MLModel, inputs: [String: MLMultiArray]) throws -> MLFeatureProvider {
    let values = inputs.mapValues { MLFeatureValue(multiArray: $0) }
    return try model.prediction(from: try MLDictionaryFeatureProvider(dictionary: values))
  }

  static func flatValues(_ array: MLMultiArray) -> [Float] {
    guard array.shape.count == 3 else { return [] }
    var values: [Float] = []
    values.reserveCapacity(array.count)
    for first in 0..<array.shape[0].intValue {
      for second in 0..<array.shape[1].intValue {
        for third in 0..<array.shape[2].intValue {
          values.append(
            array[
              [NSNumber(value: first), NSNumber(value: second), NSNumber(value: third)]
            ].floatValue
          )
        }
      }
    }
    return values
  }

  static func cropImage(_ image: CGImage, normalizedRect: CGRect) throws -> CGImage {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let left = max(0, floor(normalizedRect.minX * width))
    let top = max(0, floor(normalizedRect.minY * height))
    let right = min(width, ceil(normalizedRect.maxX * width))
    let bottom = min(height, ceil(normalizedRect.maxY * height))
    guard right > left, bottom > top else {
      throw MangaTranslationFailure.inference
    }
    let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
    guard let crop = image.cropping(to: rect) else {
      throw MangaTranslationFailure.inference
    }
    return crop
  }

  // The recognizer is trained on horizontal text lines: bring each crop
  // into reading orientation — apply the page rotation, then turn vertical
  // columns 90° counter-clockwise so their top becomes the line start.
  static func readingOrientation(
    _ image: CGImage,
    regionOrientation: MangaTextOrientation,
    pageRotation: ReaderRotation,
    context: CIContext
  ) throws -> CGImage {
    var clockwiseDegrees: Int
    switch pageRotation {
    case .none: clockwiseDegrees = 0
    case .degrees90: clockwiseDegrees = 90
    case .degrees180: clockwiseDegrees = 180
    case .degrees270: clockwiseDegrees = 270
    }
    if regionOrientation == .vertical {
      clockwiseDegrees = (clockwiseDegrees + 270) % 360
    }
    guard clockwiseDegrees != 0 else { return image }
    let exifOrientation: Int32
    switch clockwiseDegrees {
    case 90: exifOrientation = 6
    case 180: exifOrientation = 3
    case 270: exifOrientation = 8
    default: throw MangaTranslationFailure.inference
    }
    let oriented = CIImage(cgImage: image).oriented(forExifOrientation: exifOrientation)
    guard let result = context.createCGImage(oriented, from: oriented.extent) else {
      throw MangaTranslationFailure.inference
    }
    return result
  }

  static func pixelValues(_ image: CGImage, width: Int, height: Int, normalize: Bool) throws -> MLMultiArray {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
    try bytes.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      else {
        throw MangaTranslationFailure.inference
      }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let array = try MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32)
    let count = width * height * 3
    let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
    for channel in 0..<3 {
      for y in 0..<height {
        for x in 0..<width {
          let sourceIndex = (y * width + x) * 4 + channel
          let destinationIndex = channel * width * height + y * width + x
          let value = Float32(bytes[sourceIndex]) / 255
          pointer[destinationIndex] = normalize ? value * 2 - 1 : value
        }
      }
    }
    return array
  }
}
