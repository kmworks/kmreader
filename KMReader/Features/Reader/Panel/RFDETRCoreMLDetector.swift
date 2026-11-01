//
// RFDETRCoreMLDetector.swift
//
// On-device panel detector backed by RF-DETR-Medium in native Core ML (FP16), trained on Manga109-s.
// The model bakes 1/255 scale + ImageNet normalize + the 576 resize into its graph, so a page is
// squished to a 576x576 RGB image input with no manual normalization. Inference runs
// via `computeUnits = .all` (FP16 is Neural-Engine eligible). Decodes all three trained classes
// (panel/text/body) so the composition layer can frame and prune; any failure resolves to a
// whole-page fallback.
//

import CoreGraphics
@preconcurrency import CoreML
import CoreVideo
import Foundation

/// Loads the RF-DETR CoreML model once per location and runs preprocess + inference + decode off the
/// main actor, via the model's single image input (`image`, 576x576 RGB) and two outputs (boxes
/// `[1,300,4]` cxcywh-normalized, labels `[1,300,C]` class logits — auto-named by the converter,
/// so they are matched by trailing dimension).
actor RFDETRCoreMLDetector {
  static let shared = RFDETRCoreMLDetector()

  /// Raw boxes split by trained class, normalized to `[0,1]`, before any shared suppression.
  struct RawDetections: Sendable {
    var panels: [RawPanel] = []
    var texts: [RawPanel] = []
    var bodies: [RawPanel] = []
  }

  private let logger = AppLogger(.reader)
  private var model: MLModel?
  /// The location the cached model (or the failed load attempt) belongs to. A different location
  /// drops the cached model and loads again.
  private var location: PanelModelLocation?
  private var loadAttempted = false
  /// Compute units the cached model actually loaded with + the compiled model location, kept so
  /// a fallback load can later retry the preferred `.all` configuration.
  private var loadedUnits: MLComputeUnits?
  private var compiledModelURL: URL?
  /// Upgrade-retry state after a fallback load. A transient system failure (e.g. the ANE compiler
  /// service dying mid-compile) can push a capable device onto the GPU/CPU path for the rest of
  /// the session; a few spaced retries recover the Neural Engine without an app relaunch. A device
  /// that genuinely cannot compile the model burns the small budget once and stays on its fallback.
  private var upgradeAttemptsRemaining = 0
  private var upgradeNotBefore = Date.distantPast
  private var upgradeTask: Task<Void, Never>?

  private static let upgradeRetryDelays: [TimeInterval] = [30, 120, 480]

  /// Compute units to try, best first. The simulator runs CPU-only: its GPU path corrupts the
  /// model's outputs (every query scores above threshold), so there is nothing to upgrade to.
  private static let computeUnitLadder: [MLComputeUnits] = {
    #if targetEnvironment(simulator)
      return [.cpuOnly]
    #else
      return [.all, .cpuAndGPU, .cpuOnly]
    #endif
  }()

  private static let imageInputName = "image"

  /// Fixed square model input edge (RF-DETR-med). Page is squished to this — no letterbox.
  private let inputEdge = 576
  /// Class-head channels (= COCO category id). Channel 0 (manga placeholder) and the trailing
  /// spare channel are unused; the three real classes are panel/text/body.
  private let panelClass = 1
  private let textClass = 2
  private let bodyClass = 3
  private let queryCount = 300
  /// Score floor (sigmoid of the class logit). RF-DETR separates objects (~0.97) from rejects
  /// (~0.05) sharply. PANELS use a lower floor than text/body: a panel near the 0.5 line is a real but
  /// faint-bordered frame whose score flips across devices' fp16 paths (so the same page drops a panel
  /// on one chip and keeps it on another) — 0.40 stabilises those, recovering real panels (validated
  /// phantom-free across ~1000 pages; the edge-density content filter drops any blank box anyway).
  /// Text/body keep 0.5 (their downstream effects — framing, body beats — were not re-validated lower).
  private let panelScoreThreshold: Double = 0.4
  private let auxScoreThreshold: Double = 0.5

  /// Decode the page to raw boxes per class, normalized to `[0,1]`. Empty on any failure.
  func rawDetections(for image: CGImage, model location: PanelModelLocation) async -> RawDetections {
    guard let model = await loadedModel(at: location) else { return RawDetections() }
    upgradeIfDue()
    guard let pixelBuffer = makePixelBuffer(image) else { return RawDetections() }

    let started = Date()
    guard let output = predict(model, pixelBuffer) else { return RawDetections() }
    guard let (boxes, labels) = Self.locateOutputs(output) else {
      logger.error("[PanelRFCoreML] could not locate box/label outputs")
      return RawDetections()
    }
    let raw = decode(boxes: boxes, labels: labels)
    let ms = Int(Date().timeIntervalSince(started) * 1000)
    logger.debug(
      "[PanelRFCoreML] \(raw.panels.count) panel / \(raw.texts.count) text / "
        + "\(raw.bodies.count) body boxes in \(ms)ms")
    return raw
  }

  /// Synchronous, actor-isolated inference — keeps the non-Sendable `MLModel` on the actor.
  private func predict(_ model: MLModel, _ pixelBuffer: CVPixelBuffer) -> MLFeatureProvider? {
    do {
      let features = try MLDictionaryFeatureProvider(dictionary: [
        Self.imageInputName: MLFeatureValue(pixelBuffer: pixelBuffer)
      ])
      return try model.prediction(from: features)
    } catch {
      logger.error("[PanelRFCoreML] inference failed: \(error.localizedDescription)")
      return nil
    }
  }

  /// The converter auto-names the two outputs (`var_NNNN`), so identify them by trailing
  /// dimension: `[..., 4]` is the boxes tensor, the other is the class-logits tensor.
  private static func locateOutputs(_ output: MLFeatureProvider) -> (boxes: MLMultiArray, labels: MLMultiArray)? {
    var boxes: MLMultiArray?
    var labels: MLMultiArray?
    for name in output.featureNames {
      guard let arr = output.featureValue(for: name)?.multiArrayValue,
        let last = arr.shape.last?.intValue
      else { continue }
      if last == 4 { boxes = arr } else { labels = arr }
    }
    guard let boxes, let labels else { return nil }
    return (boxes, labels)
  }

  // MARK: - Preprocess

  /// Squish-resize the page to a 576x576 RGB pixel buffer (32BGRA backing; CoreML maps it to the
  /// model's RGB input). No aspect preserve, no pad — RF-DETR was trained squished, so the
  /// normalized output boxes need no inverse transform. Normalization is baked into the model.
  private func makePixelBuffer(_ image: CGImage) -> CVPixelBuffer? {
    let edge = inputEdge
    guard image.width > 0, image.height > 0 else { return nil }

    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    var pb: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault, edge, edge, kCVPixelFormatType_32BGRA,
        attrs as CFDictionary, &pb) == kCVReturnSuccess,
      let buffer = pb
    else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: edge, height: edge, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }
    ctx.interpolationQuality = .high
    // Top-left origin draw, squished to fill (the model was trained on squished input).
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
    return buffer
  }

  // MARK: - Decode

  /// 300 object queries → boxes split by class. `labels[1,300,C]`: per-class score = sigmoid of
  /// that channel (panel=1, text=2, body=3), thresholded independently — a query lands in whichever
  /// class fires. `boxes[1,300,4]`: center xywh in page-normalized `[0,1]` (squish → no un-pad).
  private func decode(boxes: MLMultiArray, labels: MLMultiArray) -> RawDetections {
    let classCount = labels.shape.last?.intValue ?? 0
    guard classCount > bodyClass,
      boxes.count >= queryCount * 4,
      labels.count >= queryCount * classCount
    else { return RawDetections() }

    var out = RawDetections()
    for q in 0..<queryCount {
      let cx = boxes[q * 4 + 0].doubleValue
      let cy = boxes[q * 4 + 1].doubleValue
      let w = boxes[q * 4 + 2].doubleValue
      let h = boxes[q * 4 + 3].doubleValue
      let x1 = Self.clamp01(cx - w / 2)
      let y1 = Self.clamp01(cy - h / 2)
      let x2 = Self.clamp01(cx + w / 2)
      let y2 = Self.clamp01(cy + h / 2)

      func box(_ score: Double) -> RawPanel {
        RawPanel(x: x1, y: y1, width: max(0, x2 - x1), height: max(0, y2 - y1), confidence: score)
      }
      func score(_ channel: Int) -> Double {
        1.0 / (1.0 + exp(-labels[q * classCount + channel].doubleValue))
      }

      let pScore = score(panelClass)
      if pScore >= panelScoreThreshold { out.panels.append(box(pScore)) }
      let tScore = score(textClass)
      if tScore >= auxScoreThreshold { out.texts.append(box(tScore)) }
      let bScore = score(bodyClass)
      if bScore >= auxScoreThreshold { out.bodies.append(box(bScore)) }
    }
    return out
  }

  private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

  // MARK: - Model

  /// Loads the model once and releases it, so Core ML builds and caches its device-specific
  /// version ahead of time. That build takes up to a minute on first load; running it right after
  /// the model is installed keeps it off the reader's first panel walk. Core ML keys the cache by
  /// model location, so `location` should be the compiled `.mlmodelc` the reader will load later.
  /// Returns whether any compute-unit configuration loaded.
  static func prepare(_ location: PanelModelLocation) async -> Bool {
    await Task.detached(priority: .utility) {
      for units in computeUnitLadder {
        let config = MLModelConfiguration()
        config.computeUnits = units
        if (try? MLModel(contentsOf: location.url, configuration: config)) != nil { return true }
      }
      return false
    }.value
  }

  private func loadedModel(at requested: PanelModelLocation) async -> MLModel? {
    if requested != location { reset(for: requested) }
    if let model { return model }
    if loadAttempted { return nil }
    loadAttempted = true

    do {
      let compiledURL =
        requested.url.pathExtension == "mlmodelc"
        ? requested.url : try await MLModel.compileModel(at: requested.url)
      // A newer location may have arrived while compiling; leave the load to it.
      guard requested == location else { return nil }
      // Pick the best compute units the device can actually build an execution plan for. Newer
      // chips run the model on the Neural Engine / GPU via `.all`; some models' ops (deformable
      // attention) cannot compile to an older ANE or GPU and fail with CoreML error -5, so fall
      // back .all → GPU → CPU. This is the device-adaptive path: capable devices stay on the ANE,
      // an A12-class device (which rejects both ANE and GPU here) lands on CPU. A fallback result
      // is not final: `upgradeIfDue` retries `.all` in the background, since the failure can be
      // a transient compile-service error rather than a capability gap.
      for units in Self.computeUnitLadder {
        let config = MLModelConfiguration()
        config.computeUnits = units
        if let loaded = try? MLModel(contentsOf: compiledURL, configuration: config) {
          model = loaded
          loadedUnits = units
          compiledModelURL = compiledURL
          if units != Self.computeUnitLadder[0] {
            upgradeAttemptsRemaining = Self.upgradeRetryDelays.count
            upgradeNotBefore = Date().addingTimeInterval(Self.upgradeRetryDelays[0])
          }
          logger.debug("[PanelRFCoreML] model loaded with computeUnits=\(Self.label(units))")
          return loaded
        }
      }
      logger.error("[PanelRFCoreML] model load failed on all compute units")
      return nil
    } catch {
      logger.error("[PanelRFCoreML] model compile failed: \(error.localizedDescription)")
      return nil
    }
  }

  /// After a fallback load, retry the preferred `.all` configuration in the background and swap
  /// the model in when it builds. Runs detached so a slow Neural Engine compile never blocks
  /// in-flight detections — the fallback model keeps serving until the swap (the two models
  /// briefly coexist during a retry; the spike is transient and the retry is rare by construction).
  private func upgradeIfDue() {
    guard model != nil, let units = loadedUnits, units != Self.computeUnitLadder[0],
      upgradeAttemptsRemaining > 0, Date() >= upgradeNotBefore,
      upgradeTask == nil, let url = compiledModelURL
    else { return }
    upgradeAttemptsRemaining -= 1
    upgradeTask = Task.detached(priority: .utility) { [self] in
      let config = MLModelConfiguration()
      config.computeUnits = Self.computeUnitLadder[0]
      let upgraded = try? MLModel(contentsOf: url, configuration: config)
      await completeUpgrade(with: upgraded, from: url)
    }
  }

  private func completeUpgrade(with upgraded: MLModel?, from url: URL) {
    // The location changed while the retry ran; its model is no longer wanted.
    guard url == compiledModelURL else { return }
    upgradeTask = nil
    if let upgraded {
      model = upgraded
      loadedUnits = Self.computeUnitLadder[0]
      upgradeAttemptsRemaining = 0
      logger.debug("[PanelRFCoreML] model upgraded to computeUnits=\(Self.label(Self.computeUnitLadder[0]))")
    } else if upgradeAttemptsRemaining > 0 {
      let index = Self.upgradeRetryDelays.count - upgradeAttemptsRemaining
      upgradeNotBefore = Date().addingTimeInterval(
        Self.upgradeRetryDelays[min(index, Self.upgradeRetryDelays.count - 1)])
    } else {
      logger.debug(
        "[PanelRFCoreML] upgrade retries exhausted, staying on computeUnits=\(Self.label(loadedUnits ?? .cpuOnly))")
    }
  }

  /// Human-readable `MLComputeUnits` name for logging (rawValues are easy to misread: `.all` is 2).
  private static func label(_ units: MLComputeUnits) -> String {
    switch units {
    case .cpuOnly: return ".cpuOnly"
    case .cpuAndGPU: return ".cpuAndGPU"
    case .all: return ".all"
    case .cpuAndNeuralEngine: return ".cpuAndNeuralEngine"
    @unknown default: return "units(\(units.rawValue))"
    }
  }

  /// Forget the cached model and any pending upgrade so the next load uses `newLocation`.
  private func reset(for newLocation: PanelModelLocation) {
    location = newLocation
    model = nil
    loadAttempted = false
    loadedUnits = nil
    compiledModelURL = nil
    upgradeAttemptsRemaining = 0
    upgradeTask?.cancel()
    upgradeTask = nil
  }
}
