//
// ApiKeyAddSheet.swift
//
//

import SwiftUI

struct ApiKeyAddSheet: View {
  let onSuccess: () -> Void
  @State private var comment = ""
  @State private var newKey: ApiKey?
  @State private var isCreating = false

  var sheetTitle: String {
    if newKey != nil {
      return String(localized: "New API Key")
    } else {
      return String(localized: "Add API Key")
    }
  }

  var body: some View {
    SheetView(title: sheetTitle, size: .medium, applyFormStyle: true) {
      Group {
        if let key = newKey {
          VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 60))
              .foregroundColor(.green)

            Text("API Key Created")
              .font(.title2)
              .bold()

            Text("Please copy your API key now. It will not be shown again.")
              .multilineTextAlignment(.center)
              .foregroundColor(.secondary)

            VStack {
              Text(key.key)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .textSelectionIfAvailable()

              #if os(iOS) || os(macOS)
                Button {
                  PlatformHelper.generalPasteboard.string = key.key
                  ErrorManager.shared.notify(
                    message: String(localized: "API key copied to clipboard"))
                } label: {
                  Label(String(localized: "Copy to Clipboard"), systemImage: AppIcon.copy)
                }
              #endif
            }
          }
        } else {
          Form {
            Section {
              VStack(alignment: .leading) {
                TextField(String(localized: "Comment"), text: $comment)
                Text(String(localized: "A comment helps you identify this API key later."))
                  .font(.footnote)
                  .foregroundColor(.secondary)
              }
            }

            Section {
              Button {
                createApiKey()
              } label: {
                HStack {
                  Spacer()
                  Label(String(localized: "Create"), systemImage: AppIcon.confirm)
                  Spacer()
                }
              }
              .disabled(comment.isEmpty || isCreating)
            }
          }
        }
      }
    }
    .onDisappear {
      if newKey != nil {
        onSuccess()
      }
    }
  }

  private func createApiKey() {
    withAnimation {
      isCreating = true
    }
    Task {
      do {
        let createdKey = try await AuthService.createApiKey(comment: comment)
        withAnimation {
          newKey = createdKey
          comment = ""
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      withAnimation {
        isCreating = false
      }
    }
  }
}
