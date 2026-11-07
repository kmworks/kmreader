//
// PanelZoomController.swift
//
//

/// Weak-target relay that retains only the latest zoom intent until Cover can lay it out.
@MainActor
final class PanelZoomController {
  private enum Command {
    case zoom(PanelRect, animated: Bool)
    case fit(animated: Bool)
  }

  private var pendingCommand: Command?

  var target: PanelZoomCommandHandling? {
    didSet { deliverPendingCommandIfPossible() }
  }

  func zoomToRect(_ rect: PanelRect, animated: Bool) {
    pendingCommand = .zoom(rect, animated: animated)
    deliverPendingCommandIfPossible()
  }

  func resetToFit(animated: Bool) {
    pendingCommand = .fit(animated: animated)
    deliverPendingCommandIfPossible()
  }

  func clearTarget(_ target: PanelZoomCommandHandling) {
    guard self.target === target else { return }
    self.target = nil
    pendingCommand = nil
  }

  func targetDidLayout() {
    deliverPendingCommandIfPossible()
  }

  private func deliverPendingCommandIfPossible() {
    guard let pendingCommand, let target, target.canReceivePanelZoomCommands else { return }
    let delivered: Bool
    switch pendingCommand {
    case .zoom(let rect, let animated):
      delivered = target.zoomToPanelRect(rect, animated: animated)
    case .fit(let animated):
      delivered = target.resetPanelZoomToFit(animated: animated)
    }
    if delivered { self.pendingCommand = nil }
  }
}
