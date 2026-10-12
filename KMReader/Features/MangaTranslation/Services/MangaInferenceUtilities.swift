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

  // Crops are cut from the unrotated source image; bring them into
  // reading orientation first. Vertical columns must stay as-is: the
  // recognizer reads upright vertical text natively, and de-rotating
  // turns every glyph sideways, which it cannot read at all.
  static func readingOrientation(
    _ image: CGImage,
    pageRotation: ReaderRotation,
    context: CIContext
  ) throws -> CGImage {
    let clockwiseDegrees: Int
    switch pageRotation {
    case .none: clockwiseDegrees = 0
    case .degrees90: clockwiseDegrees = 90
    case .degrees180: clockwiseDegrees = 180
    case .degrees270: clockwiseDegrees = 270
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
    return try chwFloatArray(bytes: bytes, width: width, height: height) { value in
      normalize ? value * 2 - 1 : value
    }
  }

  // The mobile OCR model was trained on aspect-preserved crops letterboxed onto
  // a white canvas; stretching would distort glyph proportions it relies on.
  // Resampling is done by hand: CoreGraphics scaling maps pixel centers
  // differently from the bilinear resize the model was trained with, and the
  // sub-pixel shift measurably flips glyphs.
  static func pixelValuesLetterbox(_ image: CGImage, size: Int) throws -> MLMultiArray {
    let sourceBytes = try rasterize(image)
    let scale = min(CGFloat(size) / CGFloat(image.width), CGFloat(size) / CGFloat(image.height))
    let drawnWidth = max(1, Int(CGFloat(image.width) * scale))
    let drawnHeight = max(1, Int(CGFloat(image.height) * scale))
    let resampled = bilinearResample(
      sourceBytes,
      sourceWidth: image.width,
      sourceHeight: image.height,
      targetWidth: drawnWidth,
      targetHeight: drawnHeight
    )
    let originX = (size - drawnWidth) / 2
    let originY = (size - drawnHeight) / 2
    var bytes = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<drawnHeight {
      for x in 0..<drawnWidth {
        let sourceIndex = (y * drawnWidth + x) * 4
        let destinationIndex = ((originY + y) * size + originX + x) * 4
        for channel in 0..<3 {
          bytes[destinationIndex + channel] = resampled[sourceIndex + channel]
        }
      }
    }
    return try chwFloatArray(bytes: bytes, width: size, height: size) { $0 }
  }

  private static func rasterize(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 255, count: image.width * image.height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
    try bytes.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: image.width * 4,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      else {
        throw MangaTranslationFailure.inference
      }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }

  // Separable triangle-filter resize with the reference coordinate mapping:
  // source center = (dst + 0.5) * ratio, kernel widened by the ratio when
  // shrinking, weights renormalized after edge clamping.
  private static func bilinearResample(
    _ source: [UInt8],
    sourceWidth: Int,
    sourceHeight: Int,
    targetWidth: Int,
    targetHeight: Int
  ) -> [UInt8] {
    func contributions(_ target: Int, _ ratio: Double, _ extent: Int) -> [(Int, Double)] {
      let center = (Double(target) + 0.5) * ratio
      let support = max(ratio, 1)
      let first = max(Int(floor(center - support)), 0)
      let last = min(Int(ceil(center + support)), extent)
      var result: [(Int, Double)] = []
      var total = 0.0
      for index in first..<last {
        let distance = abs((Double(index) + 0.5 - center) / support)
        guard distance < 1 else { continue }
        let weight = 1 - distance
        result.append((index, weight))
        total += weight
      }
      guard total > 0 else { return [(min(max(Int(center), 0), extent - 1), 1)] }
      return result.map { ($0.0, $0.1 / total) }
    }

    let horizontalRatio = Double(sourceWidth) / Double(targetWidth)
    let verticalRatio = Double(sourceHeight) / Double(targetHeight)
    var intermediate = [Double](repeating: 0, count: targetWidth * sourceHeight * 3)
    for y in 0..<sourceHeight {
      for x in 0..<targetWidth {
        var sums = (0.0, 0.0, 0.0)
        for (sourceX, weight) in contributions(x, horizontalRatio, sourceWidth) {
          let index = (y * sourceWidth + sourceX) * 4
          sums.0 += Double(source[index]) * weight
          sums.1 += Double(source[index + 1]) * weight
          sums.2 += Double(source[index + 2]) * weight
        }
        let target = (y * targetWidth + x) * 3
        intermediate[target] = sums.0
        intermediate[target + 1] = sums.1
        intermediate[target + 2] = sums.2
      }
    }
    var output = [UInt8](repeating: 255, count: targetWidth * targetHeight * 4)
    for y in 0..<targetHeight {
      let rows = contributions(y, verticalRatio, sourceHeight)
      for x in 0..<targetWidth {
        for channel in 0..<3 {
          var value = 0.0
          for (sourceY, weight) in rows {
            value += intermediate[(sourceY * targetWidth + x) * 3 + channel] * weight
          }
          output[(y * targetWidth + x) * 4 + channel] = UInt8(min(255, max(0, value.rounded())))
        }
      }
    }
    return output
  }

  private static func chwFloatArray(
    bytes: [UInt8],
    width: Int,
    height: Int,
    transform: (Float32) -> Float32
  ) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32)
    let count = width * height * 3
    let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
    for channel in 0..<3 {
      for y in 0..<height {
        for x in 0..<width {
          let sourceIndex = (y * width + x) * 4 + channel
          let destinationIndex = channel * width * height + y * width + x
          pointer[destinationIndex] = transform(Float32(bytes[sourceIndex]) / 255)
        }
      }
    }
    return array
  }
}
