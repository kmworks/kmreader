//
// UpdatePasswordSheet.swift
//
//

import SwiftUI

struct UpdatePasswordSheet: View {
  let authViewModel: AuthViewModel
  @Environment(\.dismiss) private var dismiss

  @State private var newPassword = ""
  @State private var confirmPassword = ""
  @State private var isUpdating = false
  @State private var showSuccessMessage = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField(String(localized: "account.details.newPassword"), text: $newPassword)
            .textContentType(.newPassword)
          SecureField(String(localized: "account.details.confirmPassword"), text: $confirmPassword)
            .textContentType(.newPassword)
        } footer: {
          if !newPassword.isEmpty && newPassword != confirmPassword {
            Text(String(localized: "Passwords do not match"))
              .foregroundColor(.red)
          }
        }

        Section {
          Button(action: updatePassword) {
            if isUpdating {
              ProgressView()
                .progressViewStyle(.circular)
            } else {
              Text(String(localized: "account.details.updatePassword"))
                .frame(maxWidth: .infinity)
            }
          }
          .adaptiveButtonStyle(.borderedProminent)
          .disabled(newPassword.isEmpty || newPassword != confirmPassword || isUpdating)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }
      .formStyle(.grouped)
      .platformNavigationTitle(String(localized: "account.details.changePassword"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Cancel")) {
            dismiss()
          }
        }
      }
      .alert(String(localized: "account.details.passwordUpdated"), isPresented: $showSuccessMessage) {
        Button(String(localized: "OK"), role: .cancel) {
          dismiss()
        }
      }
    }
  }

  private func updatePassword() {
    isUpdating = true
    Task {
      do {
        try await authViewModel.updatePassword(password: newPassword)
        showSuccessMessage = true
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isUpdating = false
    }
  }
}
