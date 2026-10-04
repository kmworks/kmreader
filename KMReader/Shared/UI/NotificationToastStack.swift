//
// NotificationToastStack.swift
//
//

import SwiftUI

/// Toasts overlap at one bottom slot: a superseded toast collapses in place while
/// the new one slides in, instead of stacking vertically.
struct NotificationToastStack: View {
  @State private var errorManager = ErrorManager.shared

  var body: some View {
    ZStack(alignment: .bottom) {
      ForEach(errorManager.notifications) { notification in
        NotificationToastView(notification: notification)
      }
    }
  }
}
