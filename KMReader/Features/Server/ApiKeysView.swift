//
// ApiKeysView.swift
//
//

import SwiftUI

struct ApiKeysView: View {
  @State private var apiKeys: [ApiKey] = []
  @State private var isLoading = false
  @State private var showingAddSheet = false
  @State private var keyToDelete: ApiKey?
  @State private var showingDeleteConfirmation = false
  @State private var lastActivities: [String: Date] = [:]
  @State private var currentApiKeyId: String?

  @State private var showRelativeDate = true

  var body: some View {
    Form {
      Section {
        if isLoading && apiKeys.isEmpty {
          ProgressView()
            .frame(maxWidth: .infinity, alignment: .center)
        } else if apiKeys.isEmpty {
          Text("No API Keys found")
            .foregroundColor(.secondary)
        } else {
          #if os(tvOS) || os(macOS)
            Button {
              withAnimation {
                showingAddSheet = true
              }
            } label: {
              HStack {
                Spacer()
                Image(systemName: AppIcon.add)
                Spacer()
              }
            }
            .adaptiveButtonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
          #endif

          ForEach(apiKeys) { apiKey in
            let isCurrentDeviceKey = apiKey.id == currentApiKeyId
            VStack(alignment: .leading) {
              HStack {
                Image(systemName: isCurrentDeviceKey ? "lock.fill" : "key")
                  .font(.footnote)
                Text(apiKey.comment.isEmpty ? String(localized: "No comment") : apiKey.comment)
                  .bold()
                if isCurrentDeviceKey {
                  Text("This device")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: .capsule)
                    .foregroundStyle(.secondary)
                }
              }
              HStack {
                Image(systemName: "calendar")
                Text("Created")
                  .foregroundColor(.secondary.opacity(0.6))
                Text(formatTime(apiKey.createdDate))
                  .monospacedDigit()
              }
              .font(.caption)
              .foregroundColor(.secondary)

              if let lastActivity = lastActivities[apiKey.id] {
                HStack {
                  Image(systemName: "clock")
                  Text("Recent activity")
                    .foregroundColor(.secondary.opacity(0.6))
                  Button {
                    showRelativeDate.toggle()
                  } label: {
                    Text(
                      showRelativeDate
                        ? lastActivity.formatted(.relative(presentation: .named))
                        : formatTime(lastActivity)
                    )
                    .monospacedDigit()
                    .contentShape(Rectangle())
                  }
                  .adaptiveButtonStyle(.plain)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .animation(.appCurve(), value: showRelativeDate)
              } else {
                HStack {
                  Image(systemName: "clock")
                  Text("No recent activity")
                }
                .font(.caption)
                .foregroundColor(.secondary)
              }
            }.tvFocusableHighlight()
              #if os(iOS) || os(macOS)
                .swipeActions {
                  if !isCurrentDeviceKey {
                    Button(role: .destructive) {
                      withAnimation {
                        keyToDelete = apiKey
                        showingDeleteConfirmation = true
                      }
                    } label: {
                      Label(String(localized: "Delete"), systemImage: AppIcon.delete)
                    }
                  }
                }
              #endif
          }
        }
      } header: {
        Text(ServerSection.apiKeys.title)
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(ServerSection.apiKeys.title)
    #if os(iOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            withAnimation {
              showingAddSheet = true
            }
          } label: {
            Image(systemName: AppIcon.add)
          }
        }
      }
    #endif
    .task {
      await loadApiKeys()
    }
    .refreshable {
      await loadApiKeys()
    }
    .alert(String(localized: "Delete API Key"), isPresented: $showingDeleteConfirmation) {
      Button(String(localized: "Delete"), role: .destructive) {
        if let key = keyToDelete {
          deleteApiKey(key)
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) {
        withAnimation {
          keyToDelete = nil
        }
      }
    } message: {
      Text(
        "Any applications or scripts using this API key will no longer be able to access the Komga API. You cannot undo this action."
      )
    }
    .sheet(isPresented: $showingAddSheet) {
      ApiKeyAddSheet {
        Task { await loadApiKeys() }
      }
    }
  }

  private func formatTime(_ date: Date) -> String {
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  private func loadApiKeys() async {
    withAnimation {
      isLoading = true
    }
    do {
      let loadedApiKeys = try await AuthService.getApiKeys()
      withAnimation {
        apiKeys = loadedApiKeys
      }
      currentApiKeyId = await resolveCurrentApiKeyId(keys: loadedApiKeys)
      for apiKey in apiKeys {
        Task {
          do {
            let activity = try await AuthService.getLatestAuthenticationActivity(
              apiKey: apiKey)
            withAnimation {
              lastActivities[apiKey.id] = activity.dateTime
            }
          } catch {
            // Ignore error for missing activity
          }
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
    withAnimation {
      isLoading = false
    }
  }

  /// The id of the API key this device uses as its instance credential, read
  /// from the instance row. Installs that logged in before the id was
  /// persisted re-identify their key by its deterministic comment, adopted
  /// only when it matches exactly one key (same-named devices can collide).
  private func resolveCurrentApiKeyId(keys: [ApiKey]) async -> String? {
    let current = AppConfig.current
    guard current.authMethod == .apiKey, !current.instanceId.isEmpty else { return nil }
    do {
      let database = try await DatabaseOperator.database()
      if let stored = try await database.fetchInstanceApiKeyId(instanceId: current.instanceId) {
        return stored
      }
      let comment = ApiKey.appManagedComment(deviceName: PlatformHelper.deviceName)
      let matches = keys.filter { $0.comment == comment }
      guard matches.count == 1, let match = matches.first else { return nil }
      try await database.updateInstanceApiKeyId(match.id, instanceId: current.instanceId)
      return match.id
    } catch {
      return nil
    }
  }

  private func deleteApiKey(_ apiKey: ApiKey) {
    // Deleting the key this device authenticates with would log the device
    // out; it can only be revoked from the Komga WebUI.
    guard apiKey.id != currentApiKeyId else { return }
    Task {
      do {
        try await AuthService.deleteApiKey(id: apiKey.id)
        if let index = apiKeys.firstIndex(where: { $0.id == apiKey.id }) {
          withAnimation {
            _ = apiKeys.remove(at: index)
          }
        }
        ErrorManager.shared.notify(message: String(localized: "notification.apiKey.deleted"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }
}
