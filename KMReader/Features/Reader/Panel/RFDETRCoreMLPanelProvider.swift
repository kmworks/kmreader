//
// RFDETRCoreMLPanelProvider.swift
//
//

import CoreGraphics
import Foundation

/// `PanelDetectionProvider` backed by the on-device RF-DETR CoreML model (GPU via `.all`).
///
/// Pre-process (squish to a 576x576 RGB pixel buffer) → CoreML predict → decode the 300 object
/// queries per class (sigmoid > 0.5, no NMS) → panels get the shared whole-page-aware suppression,
/// text/body get IoU dedup. Reading order and beat composition happen later in `PanelComposition`.
/// Any failure, or no installed model, resolves to an empty detection (whole-page fallback).
struct RFDETRCoreMLPanelProvider: PanelDetectionProvider {
  let model: PanelModelLocation?

  var version: String { "rfdetr-med-coreml-576-" + (model?.version ?? "none") }

  nonisolated func detect(image: CGImage) async -> PageDetection {
    guard let model else { return .empty }
    let raw = await RFDETRCoreMLDetector.shared.rawDetections(for: image, model: model)
    return PageDetection(
      panels: PanelDetectionNormalizer.normalize(raw.panels),
      texts: PanelDetectionNormalizer.dedupe(raw.texts),
      bodies: PanelDetectionNormalizer.dedupe(raw.bodies)
    )
  }
}
