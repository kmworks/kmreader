#if os(iOS)
  import AVFAudio
  import MediaPlayer
  import UIKit

  final class ReaderVolumeButtonHandlerView: UIView {
    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?
    var isCaptureEnabled = false {
      didSet {
        guard isCaptureEnabled != oldValue else { return }
        updateCaptureState()
      }
    }

    private let logger = AppLogger(.reader)
    private let volumeView = MPVolumeView()
    private let volumeSlider: UISlider?
    private var volumeObservation: NSKeyValueObservation?
    private var lastVolume: Float?
    private var isRestoringVolume = false
    private var volumeResetTask: Task<Void, Never>?

    override init(frame: CGRect) {
      volumeView.showsVolumeSlider = true
      volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
      super.init(frame: frame)
      isUserInteractionEnabled = false
      accessibilityElementsHidden = true

      // An attached, invisible volume view suppresses the system volume HUD.
      // Its slider restores the previous value after each hardware-button step.
      volumeView.frame = CGRect(x: -1, y: -1, width: 1, height: 1)
      volumeView.alpha = 0.001
      volumeView.isUserInteractionEnabled = false
      addSubview(volumeView)

      let notificationCenter = NotificationCenter.default
      notificationCenter.addObserver(
        self,
        selector: #selector(sceneActivationDidChange),
        name: UIScene.didActivateNotification,
        object: nil
      )
      notificationCenter.addObserver(
        self,
        selector: #selector(sceneActivationDidChange),
        name: UIScene.willDeactivateNotification,
        object: nil
      )
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      updateCaptureState()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      nil
    }

    deinit {
      volumeObservation?.invalidate()
      volumeResetTask?.cancel()
      NotificationCenter.default.removeObserver(self)
    }

    @objc private func sceneActivationDidChange() {
      updateCaptureState()
    }

    private func updateCaptureState() {
      let shouldObserve =
        isCaptureEnabled
        && window?.windowScene?.activationState == .foregroundActive
      if shouldObserve {
        startObservingVolume()
      } else {
        stopObservingVolume()
      }
    }

    private func startObservingVolume() {
      guard volumeObservation == nil else { return }
      guard volumeSlider != nil else {
        logger.error("Volume button capture unavailable: MPVolumeView has no slider")
        return
      }
      let audioSession = AVAudioSession.sharedInstance()
      let baselineVolume = min(max(audioSession.outputVolume, 0.01), 0.99)
      lastVolume = baselineVolume
      if baselineVolume != audioSession.outputVolume {
        restoreVolume(baselineVolume)
      }
      volumeObservation = audioSession.observe(\.outputVolume, options: [.new]) {
        [weak self] session, _ in
        DispatchQueue.main.async {
          self?.handleVolumeChange(session.outputVolume)
        }
      }
    }

    private func stopObservingVolume() {
      volumeObservation?.invalidate()
      volumeObservation = nil
      lastVolume = nil
      isRestoringVolume = false
      volumeResetTask?.cancel()
      volumeResetTask = nil
    }

    private func handleVolumeChange(_ newVolume: Float) {
      guard isCaptureEnabled, let previousVolume = lastVolume else { return }
      let delta = newVolume - previousVolume
      guard abs(delta) > 0.001 else { return }
      if isRestoringVolume && abs(newVolume - previousVolume) <= 0.001 {
        return
      }
      if delta > 0 {
        onVolumeUp?()
      } else {
        onVolumeDown?()
      }
      restoreVolume(previousVolume)
    }

    private func restoreVolume(_ volume: Float) {
      isRestoringVolume = true
      volumeSlider?.setValue(volume, animated: false)

      // Slider-to-session propagation can be asynchronous. Ignore its echo
      // rather than emitting a second, opposite page-turn command.
      volumeResetTask?.cancel()
      volumeResetTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        self?.isRestoringVolume = false
        self?.volumeResetTask = nil
      }
    }
  }
#endif
