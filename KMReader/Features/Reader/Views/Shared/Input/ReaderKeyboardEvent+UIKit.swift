#if os(iOS) || os(tvOS)
  import UIKit

  extension ReaderKeyboardEvent {
    init?(key: UIKey) {
      guard let readerKey = ReaderKeyboardKey(keyCode: key.keyCode) else { return nil }
      self.init(key: readerKey, modifiers: ReaderKeyboardModifiers(key.modifierFlags))
    }
  }

  extension ReaderKeyboardCommand {
    func matches(_ command: UIKeyCommand) -> Bool {
      command.input == event.key.uiKeyCommandInput
        && command.modifierFlags == UIKeyModifierFlags(event.modifiers)
    }
  }

  extension ReaderKeyboardKey {
    init?(keyCode: UIKeyboardHIDUsage) {
      switch keyCode {
      case .keyboardEscape:
        self = .escape
      case .keyboardReturnOrEnter:
        self = .returnOrEnter
      case .keyboardSpacebar:
        self = .space
      case .keyboardSlash:
        self = .slash
      case .keyboardComma:
        self = .comma
      case .keyboardH:
        self = .h
      case .keyboardC:
        self = .c
      case .keyboardL:
        self = .l
      case .keyboardT:
        self = .t
      case .keyboardJ:
        self = .j
      case .keyboardN:
        self = .n
      case .keyboardF:
        self = .f
      case .keyboardLeftArrow:
        self = .leftArrow
      case .keyboardRightArrow:
        self = .rightArrow
      case .keyboardUpArrow:
        self = .upArrow
      case .keyboardDownArrow:
        self = .downArrow
      default:
        return nil
      }
    }

    var uiKeyCommandInput: String? {
      switch self {
      case .escape:
        return UIKeyCommand.inputEscape
      case .returnOrEnter:
        return "\r"
      case .space:
        return " "
      case .slash:
        return "/"
      case .comma:
        return ","
      case .h:
        return "h"
      case .c:
        return "c"
      case .l:
        return "l"
      case .t:
        return "t"
      case .j:
        return "j"
      case .n:
        return "n"
      case .f:
        return "f"
      case .leftArrow:
        return UIKeyCommand.inputLeftArrow
      case .rightArrow:
        return UIKeyCommand.inputRightArrow
      case .upArrow:
        return UIKeyCommand.inputUpArrow
      case .downArrow:
        return UIKeyCommand.inputDownArrow
      }
    }
  }

  extension ReaderKeyboardModifiers {
    init(_ flags: UIKeyModifierFlags) {
      self = []
      if flags.contains(.shift) {
        insert(.shift)
      }
      if flags.contains(.control) {
        insert(.control)
      }
      if flags.contains(.alternate) {
        insert(.option)
      }
      if flags.contains(.command) {
        insert(.command)
      }
    }
  }

  extension UIKeyModifierFlags {
    init(_ modifiers: ReaderKeyboardModifiers) {
      self = []
      if modifiers.contains(.shift) {
        insert(.shift)
      }
      if modifiers.contains(.control) {
        insert(.control)
      }
      if modifiers.contains(.option) {
        insert(.alternate)
      }
      if modifiers.contains(.command) {
        insert(.command)
      }
    }
  }
#endif
