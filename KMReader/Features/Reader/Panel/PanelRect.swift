//
// PanelRect.swift
//
//

import CoreGraphics

nonisolated struct PanelRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * Double(size.width),
            y: y * Double(size.height),
            width: width * Double(size.width),
            height: height * Double(size.height)
        )
    }
}
