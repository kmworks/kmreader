//
// NotificationOverlay.swift
//
//

import SwiftUI

#if os(iOS)
  struct NotificationOverlay: View {
    @State private var errorManager = ErrorManager.shared

    var body: some View {
      VStack(alignment: .center) {
        Spacer()
        NotificationToastStack()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 8)
      .padding(.bottom, 64)
      .alert(String(localized: "error.title"), isPresented: $errorManager.hasAlert) {
        Button(String(localized: "OK")) {
          ErrorManager.shared.vanishError()
        }
        #if os(iOS)
          Button(String(localized: "Copy")) {
            PlatformHelper.generalPasteboard.string = errorManager.currentError?.description
            ErrorManager.shared.notify(message: String(localized: "notification.copied"))
          }
        #endif
      } message: {
        if let error = errorManager.currentError {
          Text(verbatim: error.description)
        } else {
          Text(String(localized: "error.unknown"))
        }
      }
    }
  }

#elseif os(tvOS)
  // Keep alerts in the main view hierarchy so tvOS focus reliably lands on alert actions.
  struct NotificationOverlay: View {
    @State private var errorManager = ErrorManager.shared

    var body: some View {
      VStack(alignment: .center) {
        Spacer()
        NotificationToastStack()
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 64)
      .alert(String(localized: "error.title"), isPresented: $errorManager.hasAlert) {
        Button(String(localized: "OK")) {
          ErrorManager.shared.vanishError()
        }
      } message: {
        if let error = errorManager.currentError {
          Text(verbatim: error.description)
        } else {
          Text(String(localized: "error.unknown"))
        }
      }
      .onExitCommand {
        guard errorManager.hasAlert else { return }
        ErrorManager.shared.vanishError()
      }
    }
  }

#elseif os(macOS)
  // macOS uses regular overlay approach since sheets behave differently
  struct NotificationOverlay: View {
    @State private var errorManager = ErrorManager.shared

    var body: some View {
      VStack(alignment: .center) {
        Spacer()
        NotificationToastStack()
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 64)
      .alert(String(localized: "error.title"), isPresented: $errorManager.hasAlert) {
        Button(String(localized: "OK")) {
          ErrorManager.shared.vanishError()
        }
        Button(String(localized: "Copy")) {
          PlatformHelper.generalPasteboard.string = errorManager.currentError?.description
          ErrorManager.shared.notify(message: String(localized: "notification.copied"))
        }
      } message: {
        if let error = errorManager.currentError {
          Text(verbatim: error.description)
        } else {
          Text(String(localized: "error.unknown"))
        }
      }
    }
  }
#endif
