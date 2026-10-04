//
// NotificationToastView.swift
//
//

import SwiftUI

struct NotificationToastView: View {
  let notification: AppNotification

  @State private var appeared = false
  @State private var dragOffset: CGFloat = 0
  @State private var swipedAway = false

  private var isDismissing: Bool {
    notification.dismissal != nil
  }

  private var dismissalScale: CGFloat {
    switch notification.dismissal {
    case .replaced: return 0.1
    case .expired: return 0.96
    case nil: return 1
    }
  }

  private var visibleOpacity: Double {
    if isDismissing || swipedAway { return 0 }
    return max(0.4, 1 - abs(dragOffset) / 300)
  }

  var body: some View {
    HStack(spacing: 12) {
      if notification.actionTitle != nil {
        NotificationCountdownRing(deadline: notification.deadline, lifetime: notification.lifetime)
      }
      Text(notification.message)
        .lineLimit(2)
      if let actionTitle = notification.actionTitle {
        Button {
          ErrorManager.shared.performAction(id: notification.id)
        } label: {
          Text(actionTitle)
            .fontWeight(.semibold)
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 16)
    .foregroundStyle(.primary)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 10)
    .opacity(appeared ? visibleOpacity : 0)
    .scaleEffect(appeared ? dismissalScale : 0.96)
    .offset(y: appeared ? dragOffset : 24)
    #if !os(tvOS)
      .gesture(dismissGesture)
    #endif
    .onAppear {
      withAnimation(.appSpring) {
        appeared = true
      }
    }
  }

  #if !os(tvOS)
    private var dismissGesture: some Gesture {
      DragGesture(minimumDistance: 8)
        .onChanged { value in
          dragOffset = value.translation.height
        }
        .onEnded { value in
          let translation = value.translation.height
          let velocity = value.velocity.height
          guard abs(translation) > 40 || abs(velocity) > 600 else {
            withAnimation(.appSpring) {
              dragOffset = 0
            }
            return
          }
          let direction: CGFloat = (translation != 0 ? translation : velocity) > 0 ? 1 : -1
          withAnimation(.appCurve(0.25), completionCriteria: .logicallyComplete) {
            swipedAway = true
            dragOffset = direction * 480
          } completion: {
            ErrorManager.shared.dismiss(id: notification.id)
          }
        }
    }
  #endif
}
