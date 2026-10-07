//
// TrailingOverscrollTrigger.swift
//
//

import SwiftUI

#if os(iOS)
  /// Pull-past-the-end trigger for horizontal strips: tracks trailing
  /// rubber-band overscroll, shows a chevron that arms past the trigger
  /// threshold, and fires on release. Uses ScrollGeometry/ScrollPhase, so it
  /// is iOS 18+ only; the section header link stays the entry elsewhere.
  @available(iOS 18.0, *)
  private struct TrailingOverscrollTriggerModifier: ViewModifier {
    let onTrigger: () -> Void

    @State private var overscroll: CGFloat = 0
    @State private var isDragging = false
    @State private var isArmed = false
    @State private var hasFired = false

    private let hintThreshold: CGFloat = 16
    private let triggerThreshold: CGFloat = 72

    func body(content: Content) -> some View {
      content
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
          // The scrollable range is empty when the content fits; then the
          // resting offset (the leading inset) is also the max offset.
          let maxOffsetX = max(
            -geometry.contentInsets.leading,
            geometry.contentSize.width + geometry.contentInsets.trailing
              - geometry.containerSize.width
          )
          return geometry.contentOffset.x - maxOffsetX
        } action: { _, newValue in
          overscroll = max(0, newValue)
          // Arming only happens under a finger: a momentum bounce past the
          // threshold after release must not arm.
          if isDragging {
            let armed = overscroll >= triggerThreshold
            if armed != isArmed {
              isArmed = armed
              if armed { HapticFeedback.light() }
            }
          }
          if overscroll < hintThreshold {
            hasFired = false
          }
        }
        .onScrollPhaseChange { oldPhase, newPhase in
          let wasDragging = oldPhase == .tracking || oldPhase == .interacting
          isDragging = newPhase == .tracking || newPhase == .interacting
          if wasDragging, !isDragging, isArmed, !hasFired {
            hasFired = true
            isArmed = false
            onTrigger()
          }
        }
        .overlay(alignment: .trailing) {
          if overscroll > hintThreshold {
            Image(systemName: "chevron.right")
              .font(.callout.weight(.semibold))
              .foregroundStyle(isArmed ? Color.accentColor : .secondary)
              .padding(10)
              .background(.ultraThinMaterial, in: Circle())
              .scaleEffect(isArmed ? 1.15 : 1)
              .padding(.trailing, 8)
              .allowsHitTesting(false)
          }
        }
    }
  }
#endif

extension View {
  /// Fires when the user pulls a horizontal scroll view past its trailing
  /// edge and releases. No-op outside iOS 18+.
  @ViewBuilder
  func trailingOverscrollTrigger(onTrigger: @escaping () -> Void) -> some View {
    #if os(iOS)
      if #available(iOS 18.0, *) {
        modifier(TrailingOverscrollTriggerModifier(onTrigger: onTrigger))
      } else {
        self
      }
    #else
      self
    #endif
  }
}
