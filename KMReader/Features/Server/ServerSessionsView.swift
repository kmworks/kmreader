//
// ServerSessionsView.swift
//

import SwiftUI

struct ServerSessionsView: View {
  let scope: ServerSessionScope

  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var pagination = PaginationState<ServerSession>(pageSize: 20)
  @State private var isLoading = false
  @State private var kickingSessionId: String?
  @State private var hasLoaded = false
  @State private var nativeUnsupported = false
  @State private var usesNativeAPI = false
  @State private var loadedInstanceId: String?

  init(scope: ServerSessionScope = .all) {
    self.scope = scope
  }

  var body: some View {
    Form {
      Section {
        if isLoading && !hasLoaded {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        } else if showsUnavailable {
          ContentUnavailableView {
            Label(String(localized: "Sessions Unavailable"), systemImage: "person.2")
          } description: {
            Text(String(localized: "This server does not support managing your sessions."))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        } else if pagination.isEmpty {
          ContentUnavailableView {
            Label(String(localized: "No Sessions"), systemImage: "person.2")
          } description: {
            Text(String(localized: "There are no active server sessions."))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        } else {
          ForEach(pagination.items) { session in
            ServerSessionRow(
              session: session,
              isKicking: kickingSessionId == session.id,
              canKick: kickingSessionId == nil && !session.isCurrent
            ) {
              kick(session)
            }
            .onAppear {
              loadMoreIfNeeded(session)
            }
          }
          if isLoading && hasLoaded {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          }
        }
      } footer: {
        if !pagination.isEmpty {
          Text(String(localized: "Kicking a session signs that device out immediately."))
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "Sessions"))
    .task {
      guard loadedInstanceId != current.instanceId else { return }
      loadedInstanceId = current.instanceId
      await loadSessions(refresh: true)
    }
    .refreshable {
      await loadSessions(refresh: true)
    }
  }

  private var showsUnavailable: Bool {
    nativeUnsupported && scope == .own
  }

  private func loadSessions(refresh: Bool) async {
    if refresh {
      pagination.reset()
      hasLoaded = false
    }
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      if let page = try await ManagementService.getNativeSessions(
        scope: scope, page: pagination.currentPage, size: pagination.pageSize)
      {
        usesNativeAPI = true
        nativeUnsupported = false
        apply(page)
      } else if scope == .all {
        usesNativeAPI = false
        try await loadActuatorSessions()
      } else {
        nativeUnsupported = true
      }
      hasLoaded = true
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadActuatorSessions() async throws {
    do {
      let response = try await ManagementService.getSessions()
      apply(response.sessions.map(\.serverSession), hasMore: false)
    } catch let error as APIError {
      guard !current.username.isEmpty else { throw error }
      if case .notFound = error {
        try await loadOwnActuatorSessions()
      } else if case .badRequest = error {
        try await loadOwnActuatorSessions()
      } else {
        throw error
      }
    }
  }

  private func loadOwnActuatorSessions() async throws {
    let response = try await ManagementService.getSessions(username: current.username)
    apply(response.sessions.map(\.serverSession), hasMore: false)
  }

  private func apply(_ page: Page<ServerSession>) {
    _ = pagination.applyPage(page.content)
    pagination.advance(moreAvailable: !page.last)
  }

  private func apply(_ newSessions: [ServerSession], hasMore: Bool) {
    _ = pagination.applyPage(newSessions)
    pagination.advance(moreAvailable: hasMore)
  }

  private func loadMoreIfNeeded(_ session: ServerSession) {
    guard usesNativeAPI, pagination.shouldLoadMore(after: session), !isLoading else { return }
    Task {
      await loadSessions(refresh: false)
    }
  }

  private func kick(_ session: ServerSession) {
    guard kickingSessionId == nil, !session.isCurrent else { return }
    kickingSessionId = session.id
    Task {
      do {
        if usesNativeAPI {
          try await ManagementService.deleteNativeSession(id: session.id, scope: scope)
        } else {
          try await ManagementService.deleteSession(id: session.id)
        }
        ErrorManager.shared.notify(message: String(localized: "notification.session.kicked"))
        await loadSessions(refresh: true)
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      kickingSessionId = nil
    }
  }
}
