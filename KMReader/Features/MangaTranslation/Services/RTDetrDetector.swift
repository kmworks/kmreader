import CoreGraphics
import CoreML
import Foundation

nonisolated struct RTDetrDetector: MangaTextDetecting {
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
    let logitValues = MangaInferenceUtilities.flatValues(logits)
    let boxValues = MangaInferenceUtilities.flatValues(boxes)
    guard queryCount > 0, classCount > 0,
      logitValues.count == queryCount * classCount,
      boxValues.count == queryCount * 4
    else {
      throw MangaTranslationFailure.inference
    }
    let labels = models.labels(for: "detector")
    guard !labels.isEmpty else { throw MangaTranslationFailure.modelPreparation }

    var regions: [MangaTextRegion] = []
    var highestTextScore: Float = 0
    for index in 0..<queryCount {
      try Task.checkCancellation()
      let scores = (0..<classCount).map { sigmoid(logitValues[index * classCount + $0]) }
      guard let label = scores.enumerated().max(by: { $0.element < $1.element })?.offset,
        let descriptor = labels[label], descriptor.recognize
      else {
        continue
      }
      let score = scores[label]
      highestTextScore = max(highestTextScore, score)
      guard score >= 0.3 else { continue }
      let centerX = CGFloat(boxValues[index * 4])
      let centerY = CGFloat(boxValues[index * 4 + 1])
      let width = CGFloat(boxValues[index * 4 + 2])
      let height = CGFloat(boxValues[index * 4 + 3])
      let sourceBox = CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
      let box = MangaPreparedGeometry.normalizedRect(
        for: sourceBox,
        in: image,
        splitMode: splitMode,
        rotation: rotation,
        cropRect: cropRect
      )
      guard MangaPreparedGeometry.isVisible(box) else { continue }
      let orientation = descriptor.orientation.flatMap { MangaTextOrientation(rawValue: $0) } ?? .unknown
      regions.append(
        MangaTextRegion(
          id: regions.count,
          label: label,
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

  private func sigmoid(_ value: Float) -> Float {
    1 / (1 + exp(-value))
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
        $0.label == region.label && intersectionOverUnion($0.sourceBox, region.sourceBox) >= 0.7
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
