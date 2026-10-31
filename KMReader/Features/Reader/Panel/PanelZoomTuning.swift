//
// PanelZoomTuning.swift
//
//

import CoreGraphics
import Foundation

/// Single source of truth for the panel-walk zoom feel, shared by the iOS and macOS
/// cover-engine zoom surfaces. UIKit's built-in `zoom(to:animated:)` and AppKit's
/// implicit animator both run ~0.3s by default, which reads as an abrupt jump when
/// stepping panel to panel. Slow it down a touch here.
enum PanelZoomTuning {
    /// Duration of an animated panel-to-panel zoom step, in seconds. Slowed from the ~0.3s system
    /// default so a panel-to-panel step reads as a smooth zoom rather than an abrupt jump.
    static let stepDuration: TimeInterval = 0.4

    /// Fraction of the viewport a focused panel occupies, leaving a margin that keeps a sliver
    /// of the neighboring panels visible for context. 1.0 = edge-to-edge; 0.90 = ~10% border.
    /// User-tunable via the "Panel Mode" reader setting (`AppConfig.panelZoomFillFactor`, clamped
    /// 0.75...1.0). Read per step so a change applies immediately to the next zoom.
    static var fillFactor: CGFloat { CGFloat(AppConfig.panelZoomFillFactor) }

    /// Upper bound on a single panel-step zoom, kept separate from the scroll view's pinch-zoom
    /// max so capping the walk never restricts manual pinch. Stops a tiny panel from being blown
    /// up past its native resolution (soft/blurry) or lurching the magnification: a panel that
    /// would need more simply fills less than `fillFactor` and shows extra context instead.
    static let maxStepZoom: CGFloat = 3.0
}
