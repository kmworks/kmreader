import CoreGraphics
import CoreML
import Foundation

nonisolated struct YOLOSegDetector: MangaTextDetecting {
  private static let inputSize = 640
  private static let scoreThreshold: Float = 0.3
  private static let suppressionIoU: CGFloat = 0.7

  let models: MangaModelSet
  private let logger = AppLogger(.reader)

  func detect(
    image: CGImage,
    splitMode: PageSplitMode,
    rotation: ReaderRotation,
    borderCropMode: ReaderPageBorderCropMode
  ) throws -> [MangaTextRegion] {
    let cropRect = MangaPreparedGeometry.cropRect(
      for: image,
      rotation: rotation,
      borderCropMode: borderCropMode
    )
    let detector = try models.model(component: "detector", file: "model")
    let size = Self.inputSize
    let input = try MangaInferenceUtilities.pixelValues(image, width: size, height: size, normalize: false)
    let output = try MangaInferenceUtilities.prediction(detector, inputs: ["pixel_values": input])
    // preds is [1, 37, 8400]: rows 0-3 are cx/cy/w/h in input pixels, row 4 the
    // bubble confidence (sigmoid applied in-graph); rows 5+ are mask
    // coefficients, unused because regions carry boxes only.
    guard let preds = output.featureValue(for: "preds")?.multiArrayValue else {
      throw MangaTranslationFailure.inference
    }
    let shape = preds.shape
    guard shape.count == 3, shape[0].intValue == 1, shape[1].intValue > 4, shape[2].intValue > 0
    else {
      throw MangaTranslationFailure.inference
    }
    let rows = shape[1].intValue
    let columns = shape[2].intValue
    let values = try flatValues(preds, count: rows * columns)
    let labels = models.labels(for: "detector")
    guard !labels.isEmpty else { throw MangaTranslationFailure.modelPreparation }

    let imageSize = rotation.rotatedSize(CGSize(width: image.width, height: image.height))
    var displaySize = cropRect?.size ?? imageSize
    if splitMode != .none {
      displaySize.width /= 2
    }

    var regions: [MangaTextRegion] = []
    var highestTextScore: Float = 0
    for index in 0..<columns {
      try Task.checkCancellation()
      let score = values[4 * columns + index]
      highestTextScore = max(highestTextScore, score)
      guard score >= Self.scoreThreshold, let descriptor = labels[0], descriptor.recognize else {
        continue
      }
      let centerX = CGFloat(values[index])
      let centerY = CGFloat(values[columns + index])
      let width = CGFloat(values[2 * columns + index])
      let height = CGFloat(values[3 * columns + index])
      let scale = CGFloat(size)
      let sourceBox = CGRect(
        x: (centerX - width / 2) / scale,
        y: (centerY - height / 2) / scale,
        width: width / scale,
        height: height / scale
      )
      let box = MangaPreparedGeometry.normalizedRect(
        for: sourceBox,
        in: image,
        splitMode: splitMode,
        rotation: rotation,
        cropRect: cropRect
      )
      guard MangaPreparedGeometry.isVisible(box) else { continue }
      let orientation =
        descriptor.orientation.flatMap { MangaTextOrientation(rawValue: $0) }
        ?? .infer(from: box, displaySize: displaySize)
      regions.append(
        MangaTextRegion(
          id: regions.count,
          label: 0,
          score: score,
          sourceBox: sourceBox,
          box: box,
          text: "",
          translatedText: nil,
          orientation: orientation
        )
      )
    }
    let deduplicatedRegions = deduplicated(regions: regions)
    logger.info(
      "Manga detection: \(deduplicatedRegions.count) regions, highestTextScore=\(String(format: "%.3f", highestTextScore))"
    )
    return deduplicatedRegions
  }

  private func flatValues(_ array: MLMultiArray, count: Int) throws -> [Float] {
    switch array.dataType {
    case .float32:
      let pointer = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
      return Array(UnsafeBufferPointer(start: pointer, count: count))
    case .float16:
      let pointer = array.dataPointer.bindMemory(to: Float16.self, capacity: count)
      return UnsafeBufferPointer(start: pointer, count: count).map { Float($0) }
    default:
      throw MangaTranslationFailure.inference
    }
  }

  private func intersectionOverUnion(_ first: CGRect, _ second: CGRect) -> CGFloat {
    let intersection = first.intersection(second)
    let intersectionArea = intersection.width * intersection.height
    guard intersectionArea > 0 else { return 0 }
    return intersectionArea / (first.width * first.height + second.width * second.height - intersectionArea)
  }

  private func deduplicated(regions: [MangaTextRegion]) -> [MangaTextRegion] {
    var kept: [MangaTextRegion] = []
    for region in regions.sorted(by: { $0.score > $1.score }) {
      if kept.contains(where: {
        intersectionOverUnion($0.sourceBox, region.sourceBox) >= Self.suppressionIoU
      }) {
        continue
      }
      kept.append(region)
    }
    return kept.enumerated().map {
      MangaTextRegion(
        id: $0.offset,
        label: $0.element.label,
        score: $0.element.score,
        sourceBox: $0.element.sourceBox,
        box: $0.element.box,
        text: $0.element.text,
        translatedText: $0.element.translatedText,
        orientation: $0.element.orientation
      )
    }
  }
}
