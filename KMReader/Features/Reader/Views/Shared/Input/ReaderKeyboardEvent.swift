import Foundation

enum ReaderKeyboardKey: String, Sendable {
  case escape
  case returnOrEnter
  case space
  case slash
  case comma
  case h
  case c
  case l
  case t
  case j
  case n
  case f
  case leftArrow
  case rightArrow
  case upArrow
  case downArrow
}

struct ReaderKeyboardEvent: Equatable, Hashable, Sendable {
  let key: ReaderKeyboardKey
  let modifiers: ReaderKeyboardModifiers

  init(key: ReaderKeyboardKey, modifiers: ReaderKeyboardModifiers = []) {
    self.key = key
    self.modifiers = modifiers
  }

  var hasSystemModifiers: Bool {
    modifiers.intersection(.system).isEmpty == false
  }

  func matches(_ key: ReaderKeyboardKey, modifiers expectedModifiers: ReaderKeyboardModifiers = []) -> Bool {
    self.key == key && modifiers == expectedModifiers
  }
}
