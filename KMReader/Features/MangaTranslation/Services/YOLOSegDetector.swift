import CoreGraphics
import CoreML
import Foundation

nonisolated struct YOLOSegDetector: MangaTextDetecting {
  private static let inputSize = 640
  private static let scoreThreshold: Float = 0.3

  let models: MangaModelSet

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
    let columns = shape[2].intValue
    let values = try MangaInferenceUtilities.flatValues(preds)
    let labels = models.labels(for: "detector")
    guard let descriptor = labels[0], descriptor.recognize else {
      throw MangaTranslationFailure.modelPreparation
    }
    let displaySize = MangaInferenceUtilities.detectorDisplaySize(
      for: image,
      rotation: rotation,
      cropRect: cropRect,
      splitMode: splitMode
    )
    let scale = CGFloat(size)

    var regions: [MangaTextRegion] = []
    var highestScore: Float = 0
    for index in 0..<columns {
      try Task.checkCancellation()
      let score = values[4 * columns + index]
      highestScore = max(highestScore, score)
      guard score >= Self.scoreThreshold else { continue }
      let centerX = CGFloat(values[index])
      let centerY = CGFloat(values[columns + index])
      let width = CGFloat(values[2 * columns + index])
      let height = CGFloat(values[3 * columns + index])
      let sourceBox = CGRect(
        x: (centerX - width / 2) / scale,
        y: (centerY - height / 2) / scale,
        width: width / scale,
        height: height / scale
      )
      guard
        let region = MangaInferenceUtilities.region(
          id: regions.count,
          label: 0,
          score: score,
          sourceBox: sourceBox,
          descriptor: descriptor,
          image: image,
          splitMode: splitMode,
          rotation: rotation,
          cropRect: cropRect,
          displaySize: displaySize
        )
      else { continue }
      regions.append(region)
    }
    return MangaInferenceUtilities.finalizeDetections(regions: regions, highestScore: highestScore)
  }
}
