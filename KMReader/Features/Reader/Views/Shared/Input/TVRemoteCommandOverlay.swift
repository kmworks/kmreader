#if os(tvOS)
  import SwiftUI
  import UIKit

  struct TVRemoteCommandOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let commands: [ReaderKeyboardCommand]
    let onMoveCommand: (MoveCommandDirection) -> Bool
    let onSelectCommand: () -> Bool
    let onKeyPress: (ReaderKeyboardEvent) -> Bool

    func makeCoordinator() -> Coordinator {
      Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> RemoteCaptureView {
      let view = RemoteCaptureView()
      view.backgroundColor = .clear
      view.coordinator = context.coordinator
      view.commands = commands
      view.onKeyPress = onKeyPress
      context.coordinator.installGestureRecognizersIfNeeded(on: view)
      context.coordinator.applyState(to: view)
      return view
    }

    func updateUIView(_ uiView: RemoteCaptureView, context: Context) {
      context.coordinator.parent = self
      uiView.commands = commands
      uiView.onKeyPress = onKeyPress
      context.coordinator.installGestureRecognizersIfNeeded(on: uiView)
      context.coordinator.applyState(to: uiView)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var parent: TVRemoteCommandOverlay

      private let logger = AppLogger(.reader)
      private var lastEnabledState: Bool?
      private var lastGestureDirection: MoveCommandDirection?
      private var lastGestureTimestamp: TimeInterval = 0
      private let gestureDedupInterval: TimeInterval = 0.08
      private let panTranslationThreshold: CGFloat = 32

      init(parent: TVRemoteCommandOverlay) {
        self.parent = parent
      }

      func applyState(to view: RemoteCaptureView) {
        view.isCaptureEnabled = parent.isEnabled
        view.ensureResponderState()

        if lastEnabledState != parent.isEnabled {
          logger.debug("📺 UIKit remote capture \(parent.isEnabled ? "enabled" : "disabled")")
          lastEnabledState = parent.isEnabled
        }
      }

      func installGestureRecognizersIfNeeded(on view: RemoteCaptureView) {
        guard !view.hasInstalledGestureRecognizers else { return }

        let swipeLeft = makeSwipeGesture(direction: .left)
        let swipeRight = makeSwipeGesture(direction: .right)
        let swipeUp = makeSwipeGesture(direction: .up)
        let swipeDown = makeSwipeGesture(direction: .down)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        panGesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]

        panGesture.require(toFail: swipeLeft)
        panGesture.require(toFail: swipeRight)
        panGesture.require(toFail: swipeUp)
        panGesture.require(toFail: swipeDown)

        view.addGestureRecognizer(swipeLeft)
        view.addGestureRecognizer(swipeRight)
        view.addGestureRecognizer(swipeUp)
        view.addGestureRecognizer(swipeDown)
        view.addGestureRecognizer(panGesture)
        view.hasInstalledGestureRecognizers = true
      }

      private func makeSwipeGesture(direction: UISwipeGestureRecognizer.Direction) -> UISwipeGestureRecognizer {
        let gesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        gesture.direction = direction
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        return gesture
      }

      @discardableResult
      func handlePress(_ pressType: UIPress.PressType) -> Bool {
        guard parent.isEnabled else { return false }

        switch pressType {
        case .leftArrow:
          return parent.onMoveCommand(.left)
        case .rightArrow:
          return parent.onMoveCommand(.right)
        case .upArrow:
          return parent.onMoveCommand(.up)
        case .downArrow:
          return parent.onMoveCommand(.down)
        case .select:
          return parent.onSelectCommand()
        default:
          return false
        }
      }

      @objc
      private func handleSwipeGesture(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard let direction = moveDirection(forGestureDirection: gesture.direction) else { return }
        _ = dispatchMoveCommand(direction, source: "swipe")
      }

      @objc
      private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }

        let translation = gesture.translation(in: gesture.view)
        let absoluteX = abs(translation.x)
        let absoluteY = abs(translation.y)

        guard max(absoluteX, absoluteY) >= panTranslationThreshold else { return }

        let direction: MoveCommandDirection
        if absoluteX >= absoluteY {
          direction = translation.x > 0 ? .left : .right
        } else {
          direction = translation.y > 0 ? .up : .down
        }

        _ = dispatchMoveCommand(direction, source: "pan")
      }

      private func moveDirection(forGestureDirection direction: UISwipeGestureRecognizer.Direction)
        -> MoveCommandDirection?
      {
        switch direction {
        case .left:
          return .right
        case .right:
          return .left
        case .up:
          return .down
        case .down:
          return .up
        default:
          return nil
        }
      }

      private func dispatchMoveCommand(_ direction: MoveCommandDirection, source: String) -> Bool {
        guard parent.isEnabled else { return false }

        if shouldIgnoreDuplicateGesture(direction) {
          logger.debug("📺 UIKit \(source) gesture ignored: duplicate \(String(describing: direction))")
          return false
        }

        logger.debug("📺 UIKit \(source) gesture -> move \(String(describing: direction))")
        return parent.onMoveCommand(direction)
      }

      private func shouldIgnoreDuplicateGesture(_ direction: MoveCommandDirection) -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        let isDuplicate =
          lastGestureDirection == direction
          && now - lastGestureTimestamp < gestureDedupInterval

        if !isDuplicate {
          lastGestureDirection = direction
          lastGestureTimestamp = now
        }

        return isDuplicate
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        false
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        parent.isEnabled
      }
    }

    final class RemoteCaptureView: UIView {
      weak var coordinator: Coordinator?
      var isCaptureEnabled = false
      var hasInstalledGestureRecognizers = false
      var commands: [ReaderKeyboardCommand] = []
      var onKeyPress: ((ReaderKeyboardEvent) -> Bool)?
      private var activeHandledPressTypes: Set<UIPress.PressType> = []
      private var responderRetryWorkItem: DispatchWorkItem?

      override var canBecomeFirstResponder: Bool {
        true
      }

      override var keyCommands: [UIKeyCommand]? {
        guard isCaptureEnabled else { return nil }
        return commands.compactMap(makeKeyCommand)
      }

      override func didMoveToWindow() {
        super.didMoveToWindow()
        ensureResponderState()
      }

      override func didMoveToSuperview() {
        super.didMoveToSuperview()
        ensureResponderState()
      }

      override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        DispatchQueue.main.async { [weak self] in
          self?.ensureResponderState()
        }
      }

      private func cancelResponderRetry() {
        responderRetryWorkItem?.cancel()
        responderRetryWorkItem = nil
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

      func ensureResponderState() {
        guard window != nil else { return }

        if isCaptureEnabled {
          attemptBecomeFirstResponder()
        } else {
          cancelResponderRetry()
          activeHandledPressTypes.removeAll()
          if isFirstResponder {
            resignFirstResponder()
          }
        }
      }

      override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(handleKeyCommand(_:)) {
          return isCaptureEnabled
        }
        return super.canPerformAction(action, withSender: sender)
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

      private func handlePressesBegan(_ presses: Set<UIPress>) -> Bool {
        guard let coordinator else { return false }

        var handledAny = false
        for press in presses {
          if coordinator.handlePress(press.type) {
            activeHandledPressTypes.insert(press.type)
            handledAny = true
          }
        }
        return handledAny
      }

      private func handlePressesEnded(_ presses: Set<UIPress>) -> Bool {
        guard let coordinator else { return false }

        var handledAny = false
        for press in presses {
          if activeHandledPressTypes.remove(press.type) != nil {
            handledAny = true
          } else if coordinator.handlePress(press.type) {
            handledAny = true
          }
        }
        return handledAny
      }

      private func handleKeyboardPress(_ press: UIPress) -> Bool {
        guard isCaptureEnabled else { return false }
        guard let key = press.key else { return false }
        guard let keyboardEvent = ReaderKeyboardEvent(key: key) else { return false }
        guard !keyboardEvent.modifiers.contains(.command) else { return false }
        return onKeyPress?(keyboardEvent) ?? false
      }

      override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handledAny = false
        var unhandledPresses = Set<UIPress>()

        for press in presses {
          if handleKeyboardPress(press) {
            activeHandledPressTypes.insert(press.type)
            handledAny = true
          } else {
            unhandledPresses.insert(press)
          }
        }

        if !unhandledPresses.isEmpty {
          handledAny = handlePressesBegan(unhandledPresses) || handledAny
        }

        if !handledAny {
          super.pressesBegan(presses, with: event)
        }
      }

      override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !handlePressesEnded(presses) {
          super.pressesEnded(presses, with: event)
        }
      }

      override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
          activeHandledPressTypes.remove(press.type)
        }
        super.pressesCancelled(presses, with: event)
      }

    }
  }
#endif
