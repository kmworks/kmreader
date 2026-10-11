import CoreGraphics
import CoreML
import Foundation

nonisolated struct MangaOCRRecognizer: MangaTextRecognizing {
  let models: MangaModelSet
  let tokenizer: MangaTokenizer
  private let logger = AppLogger(.reader)

  init(models: MangaModelSet) throws {
    self.models = models
    tokenizer = try MangaTokenizer(url: models.resource(component: "recognizer", file: "tokenizer"))
  }

  func recognize(crops regions: [MangaTextRegion], image: CGImage) throws -> [MangaTextRegion] {
    let encoder = try models.model(component: "recognizer", file: "encoder")
    let decoder = try models.model(component: "recognizer", file: "decoder")
    var recognized: [MangaTextRegion] = []
    for region in regions {
      let crop = try MangaInferenceUtilities.cropImage(image, normalizedRect: region.sourceBox)
      let pixels = try MangaInferenceUtilities.pixelValues(crop, width: 224, height: 224, normalize: true)
      let result = try recognize(encoder: encoder, decoder: decoder, crop: pixels)
      guard result.nonfinite == 0 else { throw MangaTranslationFailure.inference }
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
    var tokenIDs = [2]
    var generated: [Int] = []
    var nonfinite = 0
    for _ in 0..<300 {
      let actualLength = tokenIDs.count
      let paddedLength = bucketLength(actualLength)
      let result = try autoreleasepool { () throws -> (token: Int, nonfinite: Int) in
        let input = try MLMultiArray(shape: [1, NSNumber(value: paddedLength)], dataType: .int32)
        let pointer = input.dataPointer.bindMemory(to: Int32.self, capacity: paddedLength)
        for index in 0..<paddedLength {
          pointer[index] = index < actualLength ? Int32(tokenIDs[index]) : 0
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
        return nextToken(logits, position: actualLength - 1)
      }
      nonfinite += result.nonfinite
      if result.token == 3 || result.nonfinite > 0 { break }
      generated.append(result.token)
      tokenIDs.append(result.token)
    }
    return (generated, nonfinite)
  }

  private func nextToken(_ output: MLMultiArray, position: Int) -> (token: Int, nonfinite: Int) {
    let vocabularySize = output.shape[output.shape.count - 1].intValue
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
    for bucket in [1, 4, 16, 64, 128, 256, 300] where length <= bucket {
      return bucket
    }
    return 300
  }
}
