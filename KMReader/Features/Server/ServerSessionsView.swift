//
// ServerSessionsView.swift
//
//

import SwiftUI

/// Active server sessions from `/actuator/sessions` (admin only), most
/// recently active first, with per-session kick. kmrs lists every session;
/// Komga only answers the per-username variant, so the list falls back to
/// the current user's own sessions there.
struct ServerSessionsView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var sessions: [ActuatorSessionsResponse.Session] = []
  @State private var isLoading = false
  @State private var kickingSessionId: String?
  @State private var hasLoaded = false

  var body: some View {
    Form {
      Section {
        if isLoading && !hasLoaded {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        } else if sessions.isEmpty {
          ContentUnavailableView {
            Label(String(localized: "No Sessions"), systemImage: "person.2")
          } description: {
            Text(String(localized: "There are no active server sessions."))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        } else {
          ForEach(sessions) { session in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(session.id)
                  .font(.caption.monospaced())
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .textSelectionIfAvailable()
                Spacer()
                if session.expired {
                  Text(String(localized: "Expired"))
                    .font(.caption)
                    .foregroundColor(.red)
                } else {
                  Text(String(localized: "Active"))
                    .font(.caption)
                    .foregroundColor(.green)
                }
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
                Button(role: .destructive) {
                  kick(session)
                } label: {
                  if kickingSessionId == session.id {
                    ProgressView()
                  } else {
                    Text(String(localized: "Kick"))
                  }
                }
                .disabled(kickingSessionId != nil)
              }
              .font(.caption)
              .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            .tvFocusableHighlight()
          }
        }
      } footer: {
        if !sessions.isEmpty {
          Text(String(localized: "Kicking a session signs that device out immediately."))
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "Sessions"))
    .task {
      await loadSessions()
    }
    .refreshable {
      await loadSessions()
    }
  }

  private func loadSessions() async {
    isLoading = true
    do {
      let response = try await ManagementService.getSessions()
      apply(response)
    } catch let error as APIError {
      if case .notFound = error, !current.username.isEmpty {
        await loadOwnSessions()
      } else {
        ErrorManager.shared.alert(error: error)
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
    isLoading = false
  }

  private func loadOwnSessions() async {
    do {
      let response = try await ManagementService.getSessions(username: current.username)
      apply(response)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func apply(_ response: ActuatorSessionsResponse) {
    sessions = response.sessions.sorted {
      ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast)
    }
    hasLoaded = true
  }

  private func kick(_ session: ActuatorSessionsResponse.Session) {
    guard kickingSessionId == nil else { return }
    kickingSessionId = session.id
    Task {
      do {
        try await ManagementService.deleteSession(id: session.id)
        ErrorManager.shared.notify(message: String(localized: "notification.session.kicked"))
        await loadSessions()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      kickingSessionId = nil
    }
  }
}
