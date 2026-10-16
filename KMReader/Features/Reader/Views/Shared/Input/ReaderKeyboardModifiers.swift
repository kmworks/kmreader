import Foundation

struct ReaderKeyboardModifiers: OptionSet, Hashable, Sendable {
  let rawValue: Int

  static let shift = ReaderKeyboardModifiers(rawValue: 1 << 0)
  static let control = ReaderKeyboardModifiers(rawValue: 1 << 1)
  static let option = ReaderKeyboardModifiers(rawValue: 1 << 2)
  static let command = ReaderKeyboardModifiers(rawValue: 1 << 3)
  static let system: ReaderKeyboardModifiers = [.command, .option, .control]
}
