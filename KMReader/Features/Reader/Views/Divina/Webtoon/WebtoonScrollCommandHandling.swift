//
// WebtoonScrollCommandHandling.swift
//
//

@MainActor
protocol WebtoonScrollCommandHandling: AnyObject {
  func scroll(_ direction: WebtoonScrollDirection)
}
