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
    private var didActivateAudioSession = false

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
      stopObservingVolume()
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
      do {
        try audioSession.setCategory(.playback, options: [.mixWithOthers])
        try audioSession.setActive(true)
        didActivateAudioSession = true
      } catch {
        logger.error("Volume button capture failed to activate audio session: \(error)")
        return
      }
      lastVolume = baselineVolume
      restoreVolume(baselineVolume)
      volumeObservation = audioSession.observe(\.outputVolume, options: [.new]) {
        [weak self] _, change in
        guard let newVolume = change.newValue else { return }
        DispatchQueue.main.async {
          self?.handleVolumeChange(newVolume)
        }
      }
    }

    private func stopObservingVolume() {
      volumeObservation?.invalidate()
      volumeObservation = nil
      lastVolume = nil
      if didActivateAudioSession {
        do {
          try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
          logger.error("Volume button capture failed to deactivate audio session: \(error)")
        }
        didActivateAudioSession = false
      }
    }

    private func handleVolumeChange(_ newVolume: Float) {
      guard isCaptureEnabled, let previousVolume = lastVolume else { return }
      let delta = newVolume - previousVolume
      guard abs(delta) > 0.001 else { return }
      if delta > 0 {
        onVolumeUp?()
      } else {
        onVolumeDown?()
      }
      restoreVolume(previousVolume)
    }

    private func restoreVolume(_ volume: Float) {
      volumeSlider?.setValue(volume, animated: false)
    }
  }
#endif
