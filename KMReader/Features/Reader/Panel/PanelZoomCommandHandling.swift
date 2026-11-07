//
// PanelZoomCommandHandling.swift
//
//

/// Implemented by the cover engine's coordinator so `PanelZoomController` can drive
/// animated zoom on the current front slot without the module reaching into the engine.
protocol PanelZoomCommandHandling: AnyObject {
  var canReceivePanelZoomCommands: Bool { get }
  @discardableResult func zoomToPanelRect(_ rect: PanelRect, animated: Bool) -> Bool
  @discardableResult func resetPanelZoomToFit(animated: Bool) -> Bool
}
