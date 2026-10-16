//
// WebtoonScrollController.swift
//
//

@MainActor
final class WebtoonScrollController {
  weak var target: WebtoonScrollCommandHandling?

  func scroll(_ direction: WebtoonScrollDirection) {
    target?.scroll(direction)
  }

  func clearTarget(_ target: WebtoonScrollCommandHandling) {
    guard self.target === target else { return }
    self.target = nil
  }
}
