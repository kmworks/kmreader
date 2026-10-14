import Foundation

nonisolated struct MangaChatCompletionEnvelope: Decodable {
  let choices: [MangaChatChoice]
}
