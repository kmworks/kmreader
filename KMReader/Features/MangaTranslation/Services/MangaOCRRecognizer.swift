import CoreGraphics
import CoreImage
import CoreML
import Foundation

nonisolated struct MangaOCRRecognizer: MangaTextRecognizing {
  private static let beginningOfSequenceTokenID = 2
  private static let endOfSequenceTokenID = 3
  private static let paddingTokenID: Int32 = 0
  private static let maximumDecodedTokenCount = 300

  let models: MangaModelSet
  let tokenizer: MangaTokenizer
  private let logger = AppLogger(.reader)

  init(models: MangaModelSet) throws {
    self.models = models
    tokenizer = try MangaTokenizer(url: models.resource(component: "recognizer", file: "tokenizer"))
  }

  func recognize(crops regions: [MangaTextRegion], image: CGImage, rotation: ReaderRotation) throws
    -> [MangaTextRegion]
  {
    let encoder = try models.model(component: "recognizer", file: "encoder")
    let decoder = try models.model(component: "recognizer", file: "decoder")
    let ciContext = CIContext()
    var recognized: [MangaTextRegion] = []
    for region in regions {
      try Task.checkCancellation()
      let crop = try MangaInferenceUtilities.cropImage(image, normalizedRect: region.sourceBox)
      let readingCrop = try MangaInferenceUtilities.readingOrientation(
        crop, regionOrientation: region.orientation, pageRotation: rotation, context: ciContext)
      let pixels = try MangaInferenceUtilities.pixelValues(readingCrop, width: 224, height: 224, normalize: true)
      let result = try recognize(encoder: encoder, decoder: decoder, crop: pixels)
      guard result.nonfinite == 0 else { continue }
      let text = tokenizer.decode(result.tokens).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      recognized.append(
        MangaTextRegion(
          id: recognized.count,
          label: region.label,
          score: region.score,
          sourceBox: region.sourceBox,
          box: region.box,
          text: text,
          translatedText: nil,
          orientation: region.orientation
        )
      )
    }
    logger.info("Manga OCR: recognized \(recognized.count) of \(regions.count) regions")
    return recognized
  }

  private func recognize(
    encoder: MLModel,
    decoder: MLModel,
    crop: MLMultiArray
  ) throws -> (tokens: [Int], nonfinite: Int) {
    guard
      let hidden = try MangaInferenceUtilities.prediction(encoder, inputs: ["pixel_values": crop])
        .featureValue(for: "last_hidden_state")?.multiArrayValue
    else {
      throw MangaTranslationFailure.inference
    }
    var tokenIDs = [Self.beginningOfSequenceTokenID]
    var generated: [Int] = []
    var nonfinite = 0
    for _ in 0..<Self.maximumDecodedTokenCount {
      try Task.checkCancellation()
      let actualLength = tokenIDs.count
      let paddedLength = bucketLength(actualLength)
      let result = try autoreleasepool { () throws -> (token: Int, nonfinite: Int) in
        let input = try MLMultiArray(shape: [1, NSNumber(value: paddedLength)], dataType: .int32)
        let pointer = input.dataPointer.bindMemory(to: Int32.self, capacity: paddedLength)
        for index in 0..<paddedLength {
          pointer[index] = index < actualLength ? Int32(tokenIDs[index]) : Self.paddingTokenID
        }
        let mask = try MLMultiArray(shape: [1, NSNumber(value: paddedLength)], dataType: .int32)
        let maskPointer = mask.dataPointer.bindMemory(to: Int32.self, capacity: paddedLength)
        for index in 0..<paddedLength {
          maskPointer[index] = index < actualLength ? 1 : 0
        }
        let output = try MangaInferenceUtilities.prediction(
          decoder,
          inputs: [
            "input_ids": input,
            "attention_mask": mask,
            "encoder_hidden_states": hidden,
          ]
        )
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
          throw MangaTranslationFailure.inference
        }
        return try nextToken(logits, position: actualLength - 1)
      }
      nonfinite += result.nonfinite
      if result.token == Self.endOfSequenceTokenID || result.nonfinite > 0 { break }
      generated.append(result.token)
      tokenIDs.append(result.token)
    }
    return (generated, nonfinite)
  }

  private func nextToken(_ output: MLMultiArray, position: Int) throws -> (token: Int, nonfinite: Int) {
    let shape = output.shape
    guard shape.count == 3,
      shape[0].intValue == 1,
      position >= 0,
      position < shape[1].intValue,
      shape[2].intValue > 0,
      output.count == shape[1].intValue * shape[2].intValue
    else {
      throw MangaTranslationFailure.inference
    }
    let vocabularySize = shape[2].intValue
    var bestIndex = 0
    var bestValue = -Float.greatestFiniteMagnitude
    var nonfinite = 0
    for index in 0..<vocabularySize {
      let value = output[[0, NSNumber(value: position), NSNumber(value: index)]].floatValue
      if !value.isFinite { nonfinite += 1 }
      if value > bestValue {
        bestValue = value
        bestIndex = index
      }
    }
    return (bestIndex, nonfinite)
  }

  private func bucketLength(_ length: Int) -> Int {
    for bucket in [1, 4, 16, 64, 128, 256, Self.maximumDecodedTokenCount] where length <= bucket {
      return bucket
    }
    return Self.maximumDecodedTokenCount
  }
}
