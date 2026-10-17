import CoreGraphics
import CoreML
import Foundation

nonisolated struct RTDetrDetector: MangaTextDetecting {
  let boxKind: MangaTextBoxKind = .text
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
    let input = try MangaInferenceUtilities.pixelValues(image, width: 640, height: 640, normalize: false)
    let output = try MangaInferenceUtilities.prediction(detector, inputs: ["pixel_values": input])
    guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
      let boxes = output.featureValue(for: "pred_boxes")?.multiArrayValue
    else {
      throw MangaTranslationFailure.inference
    }
    let logitShape = logits.shape
    let boxShape = boxes.shape
    guard logitShape.count == 3, boxShape.count == 3,
      logitShape[0].intValue == 1, boxShape[0].intValue == 1,
      logitShape[1].intValue == boxShape[1].intValue,
      boxShape[2].intValue == 4
    else {
      throw MangaTranslationFailure.inference
    }
    let queryCount = logitShape[1].intValue
    let classCount = logitShape[2].intValue
    let logitValues = try MangaInferenceUtilities.flatValues(logits)
    let boxValues = try MangaInferenceUtilities.flatValues(boxes)
    guard queryCount > 0, classCount > 0,
      logitValues.count == queryCount * classCount,
      boxValues.count == queryCount * 4
    else {
      throw MangaTranslationFailure.inference
    }
    let labels = models.labels(for: "detector")
    guard !labels.isEmpty else { throw MangaTranslationFailure.modelPreparation }
    let displaySize = MangaInferenceUtilities.detectorDisplaySize(
      for: image,
      rotation: rotation,
      cropRect: cropRect,
      splitMode: splitMode
    )

    var regions: [MangaTextRegion] = []
    var highestScore: Float = 0
    for index in 0..<queryCount {
      try Task.checkCancellation()
      let scores = (0..<classCount).map { sigmoid(logitValues[index * classCount + $0]) }
      guard let label = scores.enumerated().max(by: { $0.element < $1.element })?.offset,
        let descriptor = labels[label], descriptor.recognize
      else {
        continue
      }
      let score = scores[label]
      highestScore = max(highestScore, score)
      guard score >= 0.3 else { continue }
      let centerX = CGFloat(boxValues[index * 4])
      let centerY = CGFloat(boxValues[index * 4 + 1])
      let width = CGFloat(boxValues[index * 4 + 2])
      let height = CGFloat(boxValues[index * 4 + 3])
      let sourceBox = CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
      guard
        let region = MangaInferenceUtilities.region(
          id: regions.count,
          label: label,
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

  private func sigmoid(_ value: Float) -> Float {
    1 / (1 + exp(-value))
  }
}
