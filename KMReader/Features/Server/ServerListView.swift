//
// ServerListView.swift
//
//

import SwiftUI

struct ServerListView: View {
  enum Mode {
    case management
    case onboarding
  }

  private let mode: Mode
  let authViewModel: AuthViewModel

  init(authViewModel: AuthViewModel, mode: Mode = .management) {
    self.authViewModel = authViewModel
    self.mode = mode
  }

  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isLoggedInV2") private var isLoggedIn: Bool = false
  @AppStorage("showProtectedServers") private var showProtectedServers: Bool = false

  @State private var allInstances: [ServerDisplayItem] = []
  @State private var instancePendingDeletion: ServerDisplayItem?
  @State private var editingInstance: ServerDisplayItem?
  @State private var showLogin = false
  @State private var showLogoutAlert = false
  @State private var protectedServerCount = 0
  @State private var isAuthenticatingProtectedServers = false

  private var isDeleteAlertPresented: Binding<Bool> {
    Binding(
      get: { instancePendingDeletion != nil },
      set: { isPresented in
        if !isPresented {
          withAnimation {
            instancePendingDeletion = nil
          }
        }
      }
    )
  }

  private var activeInstanceId: String? {
    current.instanceId.isEmpty ? nil : current.instanceId
  }

  private var canShowProtectedServers: Bool {
    showProtectedServers && LocalDeviceAuthenticationService.shared.hasProtectedAccess
  }

  private var visibleInstances: [ServerDisplayItem] {
    canShowProtectedServers ? allInstances : allInstances.filter { !$0.protected }
  }

  var body: some View {
    Form {
      if protectedServerCount > 0 {
        Section(footer: protectedServersFooter) {
          Toggle(isOn: showProtectedServersBinding) {
            Label(
              String(localized: "Show Protected Servers"),
              systemImage: canShowProtectedServers ? "eye" : "eye.slash"
            )
          }
          .disabled(isAuthenticatingProtectedServers)
        }
      }

      Section(header: introHeader, footer: footerText) {
        if visibleInstances.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
            Text(String(localized: "No servers added yet"))
              .font(.headline)
            Text(String(localized: "Add or connect to a Komga server to get started."))
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            Button {
              withAnimation {
                showLogin = true
              }
            } label: {
              Label(String(localized: "Connect to a Server"), systemImage: "plus.circle")
                .labelStyle(.titleAndIcon)
            }
            .adaptiveButtonStyle(.borderedProminent)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical)
          .listRowBackground(Color.clear)
        } else {
          ForEach(visibleInstances) { instance in
            ServerRowView(
              instance: instance,
              isGlobalSwitching: authViewModel.isSwitching,
              isSwitching: isSwitching(instance),
              isActive: isActive(instance),
              onSelect: {
                withAnimation {
                  switchTo(instance)
                }
              },
              onEdit: {
                edit(instance)
              },
              onDelete: {
                confirmDelete(instance)
              }
            )
          }
        }
      }
      .listRowBackground(Color.clear)

      if !visibleInstances.isEmpty {
        Section {
          Button {
            withAnimation {
              showLogin = true
            }
          } label: {
            HStack {
              Spacer()
              Label(addButtonTitle, systemImage: "plus.circle")
                .labelStyle(.titleAndIcon)
              Spacer()
            }
          }
        }
      }

      if mode == .management, isLoggedIn {
        Section {
          Button(role: .destructive) {
            withAnimation {
              showLogoutAlert = true
            }
          } label: {
            HStack {
              Spacer()
              Label(String(localized: "Logout"), systemImage: "rectangle.portrait.and.arrow.right")
              Spacer()
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    #if os(iOS) || os(macOS)
      .scrollContentBackground(.hidden)
    #endif
    .platformNavigationTitle(navigationTitle)
    .sheet(item: $editingInstance) { instance in
      ServerEditView(
        instance: instance,
        authViewModel: authViewModel,
        onSaved: {
          Task {
            await loadInstances()
          }
        }
      )
    }
    .alert(
      String(localized: "Delete Server"),
      isPresented: isDeleteAlertPresented,
      presenting: instancePendingDeletion
    ) { instance in
      Button(String(localized: "Delete"), role: .destructive) {
        delete(instance)
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: { instance in
      Text(
        String(
          localized:
            "This will remove \(instance.name), its credentials, and all cached data for this server."
        )
      )
    }
    .alert(String(localized: "Logout"), isPresented: $showLogoutAlert) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Logout"), role: .destructive) {
        authViewModel.logout()
        ErrorManager.shared.notify(message: String(localized: "notification.auth.loggedOut"))
      }
    } message: {
      Text(String(localized: "Are you sure you want to logout?"))
    }
    #if os(tvOS)
      // tvOS focus engine fails to reach sheet-over-sheet content, leaving only
      // the toolbar Close button focusable. Push the login form onto the
      // existing navigation stack instead of presenting a second sheet.
      .navigationDestination(isPresented: $showLogin) {
        LoginView(authViewModel: authViewModel)
        .platformNavigationTitle(String(localized: "Connect to a Server"))
      }
    #else
      .sheet(isPresented: $showLogin) {
        SheetView(title: String(localized: "Connect to a Server"), size: .large) {
          LoginView(authViewModel: authViewModel)
        }
      }
    #endif
    .task {
      resetProtectedVisibilityIfNeeded()
      await loadInstances()
    }
    .onAppear {
      resetProtectedVisibilityIfNeeded()
    }
    .onChange(of: showLogin) { _, isPresented in
      if !isPresented {
        Task {
          await loadInstances()
        }
      }
    }
    .onChange(of: isLoggedIn) { _, loggedIn in
      Task {
        await loadInstances()
      }
      if loggedIn && mode == .onboarding {
        dismiss()
      }
    }
  }

  private var navigationTitle: String {
    switch mode {
    case .management:
      return String(localized: "Servers")
    case .onboarding:
      return String(localized: "Get Started")
    }
  }

  @ViewBuilder
  private var introHeader: some View {
    switch mode {
    case .management:
      EmptyView()
    case .onboarding:
      Text(String(localized: "Choose an existing Komga server or add a new one to begin."))
        .font(.subheadline)
        .textCase(nil)
        .padding(.vertical)
    }
  }

  private var footerText: some View {
    Text("Credentials are stored locally so you can switch servers without re-entering them.")
      .foregroundStyle(.secondary)
  }

  private var addButtonTitle: LocalizedStringKey {
    switch mode {
    case .management:
      return "Add Another Server"
    case .onboarding:
      return "Connect to a Server"
    }
  }

  private func isActive(_ instance: ServerDisplayItem) -> Bool {
    activeInstanceId == instance.instanceId
  }

  private func isSwitching(_ instance: ServerDisplayItem) -> Bool {
    authViewModel.isSwitching && authViewModel.switchingInstanceId == instance.instanceId
  }

  private func switchTo(_ instance: ServerDisplayItem) {
    guard !isActive(instance) else { return }
    Task {
      let success = await authViewModel.switchTo(instance: instance)
      if success {
        do {
          let database = try await DatabaseOperator.database()
          await database.updateInstanceLastUsed(instanceId: instance.instanceId)
          await loadInstances()
        } catch {
          ErrorManager.shared.alert(error: error)
        }
      }
    }
  }

  private func delete(_ instance: ServerDisplayItem) {
    Task {
      if isActive(instance) {
        authViewModel.logout()
      }

      let instanceId = instance.instanceId
      LibraryManager.shared.removeLibraries(for: instanceId)

      do {
        let database = try await DatabaseOperator.database()
        try await database.deleteServerDisplayItem(id: instance.id)
        await loadInstances()
        ErrorManager.shared.notify(message: String(localized: "notification.server.deleted"))
        withAnimation {
          instancePendingDeletion = nil
        }
      } catch {
        ErrorManager.shared.alert(error: error)
        return
      }

      await SyncService.clearInstanceData(instanceId: instanceId)
      await OfflineManager.shared.cancelAllDownloads()
      OfflineManager.removeOfflineData(for: instanceId)
      CacheManager.clearCaches(instanceId: instanceId)
    }
  }

  private func loadInstances() async {
    do {
      let database = try await DatabaseOperator.database()
      let loadedInstances = try await database.fetchServerDisplayItems(includeProtected: true)
      let loadedProtectedServerCount = loadedInstances.filter(\.protected).count
      withAnimation {
        if protectedServerCount != loadedProtectedServerCount {
          protectedServerCount = loadedProtectedServerCount
        }
        if allInstances != loadedInstances {
          allInstances = loadedInstances
        }
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private var showProtectedServersBinding: Binding<Bool> {
    Binding(
      get: { canShowProtectedServers },
      set: { newValue in
        if newValue {
          authenticateAndShowProtectedServers()
        } else {
          withAnimation {
            showProtectedServers = false
          }
        }
      }
    )
  }

  private func resetProtectedVisibilityIfNeeded() {
    guard showProtectedServers else { return }
    guard !LocalDeviceAuthenticationService.shared.hasProtectedAccess else { return }
    showProtectedServers = false
  }

  private var protectedServersFooter: some View {
    Text(
      String(
        localized:
          "Protected servers are hidden from this list until you authenticate with device passcode, Touch ID, or Face ID."
      )
    )
    .foregroundStyle(.secondary)
  }

  private func authenticateAndShowProtectedServers() {
    guard !isAuthenticatingProtectedServers else { return }
    guard LocalDeviceAuthenticationService.shared.canAuthenticate else {
      ErrorManager.shared.notify(
        message: String(localized: "Device authentication is not available on this device."))
      return
    }

    isAuthenticatingProtectedServers = true
    Task {
      let authenticated = await LocalDeviceAuthenticationService.shared.authenticateProtectedAccess(
        reason: String(localized: "Authenticate to show protected servers.")
      )
      if authenticated {
        withAnimation {
          showProtectedServers = true
        }
      }
      isAuthenticatingProtectedServers = false
    }
  }

  private func edit(_ instance: ServerDisplayItem) {
    Task {
      guard await authenticateProtectedServerActionIfNeeded(instance) else { return }
      withAnimation {
        editingInstance = instance
      }
    }
  }

  private func confirmDelete(_ instance: ServerDisplayItem) {
    Task {
      guard await authenticateProtectedServerActionIfNeeded(instance) else { return }
      withAnimation {
        instancePendingDeletion = instance
      }
    }
  }

  private func authenticateProtectedServerActionIfNeeded(_ instance: ServerDisplayItem) async -> Bool {
    guard instance.protected else { return true }
    let authenticated = await LocalDeviceAuthenticationService.shared.authenticateProtectedAccess(
      reason: String(localized: "Authenticate to show protected servers.")
    )
    if !authenticated {
      withAnimation {
        showProtectedServers = false
      }
    }
    return authenticated
  }

}
