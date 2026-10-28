//
// ServerSessionRow.swift
//

import SwiftUI

struct ServerSessionRow: View {
  let session: ServerSession
  let isKicking: Bool
  let canKick: Bool
  let onKick: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(session.id)
          .font(.caption.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelectionIfAvailable()
        Spacer()
        if session.isCurrent {
          Text(String(localized: "Current"))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text(session.expired ? String(localized: "Expired") : String(localized: "Active"))
            .font(.caption)
            .foregroundStyle(session.expired ? .red : .green)
        }
      }
      if let email = session.email {
        Text(email)
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if let userId = session.userId {
        Text(userId)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      HStack {
        if let createdAt = session.createdAt {
          Text(
            String.localizedStringWithFormat(
              String(localized: "session.created", defaultValue: "Created %@"),
              createdAt.formatted(.relative(presentation: .named))
            )
          )
        }
        if let lastAccessedAt = session.lastAccessedAt {
          Text("·")
          Text(
            String.localizedStringWithFormat(
              String(localized: "session.lastActive", defaultValue: "Active %@"),
              lastAccessedAt.formatted(.relative(presentation: .named))
            )
          )
        }
        Spacer()
        if !session.isCurrent {
          Button(role: .destructive, action: onKick) {
            Group {
              if isKicking {
                ProgressView()
              } else {
                Text(String(localized: "Kick"))
              }
            }
            .contentShape(Rectangle())
          }
          .disabled(!canKick)
        }
      }
      .font(.caption)
      .foregroundColor(.secondary)
    }
    .padding(.vertical, 2)
    .tvFocusableHighlight()
  }
}
