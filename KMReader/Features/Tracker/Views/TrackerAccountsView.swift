//
// TrackerAccountsView.swift
//

import SwiftUI

struct TrackerAccountsView: View {
  @AppStorage("currentAccount") private var current: Current = .init()

  @State private var accounts: [TrackerProvider: TrackerAccount] = [:]
  @State private var preferences: TrackerPreferences?
  @State private var libraries: [LibraryInfo] = []
  @State private var isLoading = false
  @State private var isSavingPreferences = false
  @State private var pendingProvider: TrackerProvider?
  @State private var disconnectingProvider: TrackerProvider?
  @State private var showDisconnectConfirmation = false
  @State private var loadedInstanceId: String?
  @State private var hasLoaded = false

  private var webURL: URL? {
    URL(string: current.serverURL + "/account/trackers")
  }

  var body: some View {
    Form {
      if !hasLoaded && isLoading {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if !hasLoaded {
        Section {
          ContentUnavailableView {
            Label(String(localized: "Trackers Unavailable"), systemImage: "arrow.triangle.2.circlepath")
          } description: {
            Text(String(localized: "This server does not support reading trackers, or it could not be reached."))
          }
        }
      } else {
        Section {
          ForEach(TrackerProvider.allCases, id: \.self) { provider in
            TrackerAccountRow(
              provider: provider,
              account: accounts[provider],
              isPending: pendingProvider == provider,
              webURL: webURL
            ) {
              disconnectingProvider = provider
              showDisconnectConfirmation = true
            }
          }
        } header: {
          Text(String(localized: "Connected Accounts"))
        } footer: {
          Text(
            String(
              localized: "Connect tracker accounts in the server web interface. KMReader never stores provider tokens.")
          )
        }

        if preferences != nil {
          Section(header: Text(String(localized: "Preferences"))) {
            Picker(String(localized: "Default Tracker"), selection: defaultTrackerBinding) {
              Text(String(localized: "None")).tag(TrackerProvider?.none)
              ForEach(TrackerProvider.allCases, id: \.self) { provider in
                Text(provider.displayName).tag(TrackerProvider?.some(provider))
              }
            }
            .disabled(isSavingPreferences)

            NavigationLink(String(localized: "Libraries")) {
              TrackerLibrarySelectionView(
                libraries: libraries,
                selectedIds: librarySelectionBinding
              )
            }
          }
        }

        Section {
          NavigationLink(value: NavDestination.settingsTrackerBindings) {
            Label(String(localized: "Linked Series"), systemImage: "link")
          }
          NavigationLink(value: NavDestination.settingsTrackerLedger) {
            Label(String(localized: "Recent Manual Updates"), systemImage: "clock.arrow.circlepath")
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "Trackers"))
    .task(id: current.instanceId) {
      guard loadedInstanceId != current.instanceId else { return }
      loadedInstanceId = current.instanceId
      await load()
    }
    .refreshable {
      await load()
    }
    .alert(
      String(localized: "Disconnect Tracker"),
      isPresented: $showDisconnectConfirmation,
      presenting: disconnectingProvider
    ) { provider in
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Disconnect"), role: .destructive) { logout(provider) }
    } message: { provider in
      Text(
        String.localizedStringWithFormat(
          String(
            localized:
              "Disconnecting %@ removes its authorization from the server. You will need to connect again in the server web interface."
          ),
          provider.displayName
        ))
    }
  }

  private var defaultTrackerBinding: Binding<TrackerProvider?> {
    Binding(
      get: { preferences?.defaultTracker },
      set: { value in
        preferences?.defaultTracker = value
        savePreferences()
      }
    )
  }

  private var librarySelectionBinding: Binding<Set<String>> {
    Binding(
      get: { Set(preferences?.libraries ?? []) },
      set: { value in
        preferences?.libraries = value.sorted()
        savePreferences()
      }
    )
  }

  private func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }
    do {
      let loadedPreferences = try await TrackerService.getPreferences()
      preferences = loadedPreferences
      TrackerCapabilityStore.shared.updatePreferences(loadedPreferences)
      libraries = try await DatabaseOperator.database().fetchLibraries(
        instanceId: current.instanceId
      ).filter { $0.id != KomgaLibrary.allLibrariesId }
      try await loadAccounts()
      TrackerCapabilityStore.shared.refreshCompleted(supported: true)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private func loadAccounts() async throws {
    var loaded: [TrackerProvider: TrackerAccount] = [:]
    for provider in TrackerProvider.allCases {
      loaded[provider] = try await TrackerService.getAccount(provider: provider)
    }
    accounts = loaded
  }

  private func logout(_ provider: TrackerProvider) {
    guard pendingProvider == nil else { return }
    pendingProvider = provider
    Task {
      do {
        try await TrackerService.logout(provider: provider)
        accounts[provider] = TrackerAccount(loggedIn: false, username: nil)
        ErrorManager.shared.notify(message: String(localized: "Tracker disconnected."))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      pendingProvider = nil
    }
  }

  private func savePreferences() {
    guard let preferences, !isSavingPreferences else { return }
    isSavingPreferences = true
    Task {
      do {
        self.preferences = try await TrackerService.updatePreferences(preferences)
        TrackerCapabilityStore.shared.updatePreferences(self.preferences ?? preferences)
        ErrorManager.shared.notify(message: String(localized: "Tracker preferences saved."))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isSavingPreferences = false
    }
  }
}
