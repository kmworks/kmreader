import Foundation

nonisolated struct ModelPackageLabel: Codable, Hashable, Sendable {
  let name: String
  let recognize: Bool
  let orientation: String?

  init(name: String, recognize: Bool, orientation: String? = nil) {
    self.name = name
    self.recognize = recognize
    self.orientation = orientation
  }

  var isValid: Bool {
    guard !name.isEmpty else { return false }
    guard let orientation else { return true }
    return ["unknown", "horizontal", "vertical"].contains(orientation)
  }
}
