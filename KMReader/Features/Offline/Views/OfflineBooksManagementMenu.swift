//
// OfflineBooksManagementMenu.swift
//
//

import SwiftUI

struct OfflineBooksManagementMenu: View {
  let canRemoveReadBooks: Bool
  let isScanning: Bool
  let onRemoveRead: () -> Void
  let onCleanupOrphanedFiles: () -> Void
  let onRemoveAll: () -> Void

  var body: some View {
    Menu {
      Section {
        Button(role: .destructive) {
          onRemoveRead()
        } label: {
          Label(
            String(localized: "settings.offline_books.remove_read"),
            systemImage: ReadStatus.read.icon)
        }
        .disabled(!canRemoveReadBooks)

        Button {
          onCleanupOrphanedFiles()
        } label: {
          Label(
            String(localized: "settings.offline_books.cleanup_orphaned"),
            systemImage: "arrow.3.trianglepath"
          )
        }
        .disabled(isScanning)
      }

      Section {
        Button(role: .destructive) {
          onRemoveAll()
        } label: {
          Label(String(localized: "settings.offline_books.remove_all"), systemImage: AppIcon.delete)
        }
      }
    } label: {
      HStack(spacing: 6) {
        if isScanning {
          ProgressView()
            .controlSize(.small)
        }
        Label(String(localized: "Manage"), systemImage: AppIcon.more)
      }
    }
  }
}
