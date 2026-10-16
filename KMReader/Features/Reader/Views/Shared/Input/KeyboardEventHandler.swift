//
// KeyboardEventHandler.swift
//
//

import SwiftUI

#if os(macOS)
  import AppKit

  struct KeyboardEventHandler: NSViewRepresentable {
    let isEnabled: Bool
    let commands: [ReaderKeyboardCommand]
    let onKeyPress: (ReaderKeyboardEvent) -> Bool

    init(
      isEnabled: Bool = true,
      commands: [ReaderKeyboardCommand] = [],
      onKeyPress: @escaping (ReaderKeyboardEvent) -> Bool
    ) {
      self.isEnabled = isEnabled
      self.commands = commands
      self.onKeyPress = onKeyPress
    }

    func makeNSView(context: Context) -> KeyboardHandlerView {
      let view = KeyboardHandlerView()
      view.isCaptureEnabled = isEnabled
      view.onKeyPress = onKeyPress
      return view
    }

    func updateNSView(_ nsView: KeyboardHandlerView, context: Context) {
      nsView.isCaptureEnabled = isEnabled
      nsView.onKeyPress = onKeyPress
      nsView.ensureResponderState()
    }
  }

  class KeyboardHandlerView: NSView {
    var isCaptureEnabled = true
    var onKeyPress: ((ReaderKeyboardEvent) -> Bool)?
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool {
      isCaptureEnabled
    }

    override func becomeFirstResponder() -> Bool {
      isCaptureEnabled
    }

    override func keyDown(with event: NSEvent) {
      guard let keyboardEvent = ReaderKeyboardEvent(event: event) else {
        super.keyDown(with: event)
        return
      }

      let handled = isCaptureEnabled && (onKeyPress?(keyboardEvent) ?? false)
      if !handled {
        super.keyDown(with: event)
      }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      ensureResponderState()
      installMonitorIfNeeded()
    }

    override func removeFromSuperview() {
      super.removeFromSuperview()
      teardownMonitor()
    }

    // Don't intercept mouse events - let them pass through
    override func hitTest(_ point: NSPoint) -> NSView? {
      return nil
    }

    func ensureResponderState() {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if isCaptureEnabled {
          window?.makeFirstResponder(self)
        } else if window?.firstResponder === self {
          window?.makeFirstResponder(nil)
        }
      }
    }

    private func installMonitorIfNeeded() {
      guard keyMonitor == nil else { return }
      keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, let window = self.window, window.isKeyWindow else { return event }
        guard self.isCaptureEnabled, let keyboardEvent = ReaderKeyboardEvent(event: event) else {
          return event
        }
        let handled = self.onKeyPress?(keyboardEvent) ?? false
        return handled ? nil : event
      }
    }

    private func teardownMonitor() {
      guard let keyMonitor else { return }
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  extension ReaderKeyboardEvent {
    fileprivate init?(event: NSEvent) {
      guard let key = ReaderKeyboardKey(keyCode: event.keyCode) else { return nil }
      self.init(key: key, modifiers: ReaderKeyboardModifiers(event.modifierFlags))
    }
  }

  extension ReaderKeyboardKey {
    fileprivate init?(keyCode: UInt16) {
      switch keyCode {
      case 53:
        self = .escape
      case 36:
        self = .returnOrEnter
      case 49:
        self = .space
      case 44:
        self = .slash
      case 43:
        self = .comma
      case 4:
        self = .h
      case 8:
        self = .c
      case 37:
        self = .l
      case 17:
        self = .t
      case 38:
        self = .j
      case 45:
        self = .n
      case 3:
        self = .f
      case 123:
        self = .leftArrow
      case 124:
        self = .rightArrow
      case 126:
        self = .upArrow
      case 125:
        self = .downArrow
      default:
        return nil
      }
    }
  }

  extension ReaderKeyboardModifiers {
    fileprivate init(_ flags: NSEvent.ModifierFlags) {
      self = []
      if flags.contains(.shift) {
        insert(.shift)
      }
      if flags.contains(.control) {
        insert(.control)
      }
      if flags.contains(.option) {
        insert(.option)
      }
      if flags.contains(.command) {
        insert(.command)
      }
    }
  }
#elseif os(iOS) || os(tvOS)
  import UIKit

  struct KeyboardEventHandler: UIViewRepresentable {
    let isEnabled: Bool
    let commands: [ReaderKeyboardCommand]
    let onKeyPress: (ReaderKeyboardEvent) -> Bool

    init(
      isEnabled: Bool = true,
      commands: [ReaderKeyboardCommand] = [],
      onKeyPress: @escaping (ReaderKeyboardEvent) -> Bool
    ) {
      self.isEnabled = isEnabled
      self.commands = commands
      self.onKeyPress = onKeyPress
    }

    func makeUIView(context: Context) -> KeyboardHandlerView {
      let view = KeyboardHandlerView()
      view.isCaptureEnabled = isEnabled
      view.commands = commands
      view.onKeyPress = onKeyPress
      return view
    }

    func updateUIView(_ uiView: KeyboardHandlerView, context: Context) {
      uiView.isCaptureEnabled = isEnabled
      uiView.commands = commands
      uiView.onKeyPress = onKeyPress
      uiView.ensureResponderState()
    }
  }

  class KeyboardHandlerView: UIView {
    var isCaptureEnabled = true {
      didSet {
        guard isCaptureEnabled != oldValue else { return }
        scheduleResponderStateUpdate()
      }
    }
    var commands: [ReaderKeyboardCommand] = []
    var onKeyPress: ((ReaderKeyboardEvent) -> Bool)?
    private var responderRetryWorkItem: DispatchWorkItem?
    private var responderStateWorkItem: DispatchWorkItem?

    override var canBecomeFirstResponder: Bool {
      isCaptureEnabled
    }

    override var keyCommands: [UIKeyCommand]? {
      guard isCaptureEnabled else { return nil }
      return commands.compactMap(makeKeyCommand)
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      scheduleResponderStateUpdate()
    }

    override func didMoveToSuperview() {
      super.didMoveToSuperview()
      scheduleResponderStateUpdate()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      nil
    }

    func ensureResponderState() {
      scheduleResponderStateUpdate()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
      if action == #selector(handleKeyCommand(_:)) {
        return isCaptureEnabled
      }
      return super.canPerformAction(action, withSender: sender)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      guard isCaptureEnabled else {
        super.pressesBegan(presses, with: event)
        return
      }

      let unhandledPresses = Set(presses.filter { !handlePress($0) })
      if !unhandledPresses.isEmpty {
        super.pressesBegan(unhandledPresses, with: event)
      }
    }

    private func makeKeyCommand(_ command: ReaderKeyboardCommand) -> UIKeyCommand? {
      guard command.event.modifiers.contains(.command) else { return nil }
      guard let input = command.event.key.uiKeyCommandInput else { return nil }

      let keyCommand = UIKeyCommand(
        input: input,
        modifierFlags: UIKeyModifierFlags(command.event.modifiers),
        action: #selector(handleKeyCommand(_:))
      )
      keyCommand.discoverabilityTitle = command.title
      return keyCommand
    }

    @objc
    private func handleKeyCommand(_ sender: UIKeyCommand) {
      guard isCaptureEnabled else { return }
      guard let command = commands.first(where: { $0.matches(sender) }) else { return }
      _ = onKeyPress?(command.event)
    }

    private func handlePress(_ press: UIPress) -> Bool {
      guard let key = press.key else { return false }
      guard let keyboardEvent = ReaderKeyboardEvent(key: key) else { return false }

      guard !keyboardEvent.modifiers.contains(.command) else {
        return false
      }

      return onKeyPress?(keyboardEvent) ?? false
    }

    private func cancelResponderRetry() {
      responderRetryWorkItem?.cancel()
      responderRetryWorkItem = nil
    }

    private func cancelResponderStateUpdate() {
      responderStateWorkItem?.cancel()
      responderStateWorkItem = nil
    }

    private func scheduleResponderStateUpdate() {
      cancelResponderRetry()
      cancelResponderStateUpdate()

      let workItem = DispatchWorkItem { [weak self] in
        guard let self, self.window != nil else { return }

        if self.isCaptureEnabled {
          self.attemptBecomeFirstResponder()
        } else if self.isFirstResponder {
          self.resignFirstResponder()
        }
      }

      responderStateWorkItem = workItem
      DispatchQueue.main.async(execute: workItem)
    }

    private func attemptBecomeFirstResponder(attemptsLeft: Int = 8) {
      guard window != nil, isCaptureEnabled else { return }

      if !isFirstResponder {
        becomeFirstResponder()
      }

      guard !isFirstResponder, attemptsLeft > 0 else { return }

      cancelResponderRetry()
      let workItem = DispatchWorkItem { [weak self] in
        self?.attemptBecomeFirstResponder(attemptsLeft: attemptsLeft - 1)
      }
      responderRetryWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
    }
  }
#endif
