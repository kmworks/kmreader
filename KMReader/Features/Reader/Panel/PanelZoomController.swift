//
// PanelZoomController.swift
//
//

/// Weak-target command relay that drives panel zoom on the cover engine. Mirrors
/// `WebtoonScrollController`: a plain `@MainActor final class` injected from
/// `DivinaReaderView`, whose `target` is bound once to the cover coordinator. It is
/// NOT `@Observable` and is NOT drained in `updateUIView`.
@MainActor
final class PanelZoomController {
    weak var target: PanelZoomCommandHandling?

    func zoomToRect(_ rect: PanelRect, animated: Bool) {
        target?.zoomToPanelRect(rect, animated: animated)
    }

    func resetToFit(animated: Bool) {
        target?.resetPanelZoomToFit(animated: animated)
    }

    func clearTarget(_ target: PanelZoomCommandHandling) {
        guard self.target === target else { return }
        self.target = nil
    }
}
