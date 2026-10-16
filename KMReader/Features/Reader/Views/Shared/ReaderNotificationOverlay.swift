import SwiftUI

struct ReaderNotificationOverlay: View {
  var body: some View {
    NotificationToastStack()
      .padding(.horizontal, 16)
      #if os(iOS) || os(tvOS)
        .padding(.bottom, 88)
      #else
        .padding(.bottom, 32)
      #endif
  }
}
