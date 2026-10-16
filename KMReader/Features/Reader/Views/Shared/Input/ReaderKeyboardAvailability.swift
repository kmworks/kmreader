import Foundation
import GameController

enum ReaderKeyboardAvailability {
  static var shouldAutoShowKeyboardHelp: Bool {
    #if os(macOS)
      true
    #elseif os(iOS) || os(tvOS)
      GCKeyboard.coalesced != nil
    #else
      false
    #endif
  }
}
