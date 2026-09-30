//
// ContentView.swift
//
//

import SwiftUI

struct ContentView: View {
  private enum ProtectedAccessGate: Equatable {
    case checking
    case unlocked(instanceId: String, protected: Bool)
  }

  let authViewModel: AuthViewModel
  let readerPresentation: ReaderPresentationManager
  @Environment(\.scenePhase) private var scenePhase

  @AppStorage("isLoggedInV2") private var isLoggedIn: Bool = false
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("enableSSE") private var enableSSE: Bool = true
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("privacyProtection") private var privacyProtection: Bool = false

  @State private var showPrivacyBlur = false
  @State private var protectedAccessGate: ProtectedAccessGate = .checking

  #if os(iOS) || os(tvOS)
    @Namespace private var zoomNamespace
  #endif

  private var syncViewModel: SyncViewModel {
    SyncViewModel.shared
  }

  private var context: AppViewContext {
    AppViewContext(
      authViewModel: authViewModel,
      readerPresentation: readerPresentation
    )
  }

  private var isReady: Bool {
    hasRenderableAccessForCurrentInstance
      && (authViewModel.bootstrapState == .ready || isOffline)
      && !syncViewModel.isSyncing
  }

  private var hasRenderableAccessForCurrentInstance: Bool {
    guard case .unlocked(let instanceId, _) = protectedAccessGate else {
      return false
    }
    return instanceId == current.instanceId
  }

  private var shouldReauthenticateProtectedCurrentInstance: Bool {
    guard case .unlocked(let instanceId, let protected) = protectedAccessGate else {
      return false
    }
    return instanceId == current.instanceId
      && protected
      && !LocalDeviceAuthenticationService.shared.hasProtectedAccess
  }

  private var protectedAccessTaskID: String {
    guard isLoggedIn else { return "logged-out" }
    return current.instanceId
  }

  private var automaticReadingHistorySyncTrigger: String {
    guard isLoggedIn, authViewModel.bootstrapState == .ready, !isOffline, !current.instanceId.isEmpty
    else {
      return ""
    }
    return current.instanceId
  }

  var body: some View {
    Group {
      if isLoggedIn {
        Group {
          if isReady {
            #if os(macOS)
              MainSplitView(context: context)
            #elseif os(iOS)
              if PlatformHelper.isPad {
                MainSplitView(context: context)
              } else {
                if #available(iOS 18.0, *) {
                  PhoneTabView(context: context)
                } else {
                  OldTabView(context: context)
                }
              }
            #elseif os(tvOS)
              if #available(tvOS 18.0, *) {
                TVTabView(context: context)
              } else {
                OldTabView(context: context)
              }
            #endif
          } else {
            SplashView(syncViewModel: syncViewModel) {
              AppConfig.enterAutoOfflineMode()
            }
          }
        }
        .task(id: protectedAccessTaskID) {
          guard isLoggedIn else { return }
          guard await unlockProtectedCurrentInstanceForRendering() else { return }
          await DashboardLibrarySelectionStore.loadSelection(
            for: current.instanceId,
            preferCachedIfUnset: true
          )
          // Read list continuation is local state: load it with the instance,
          // independent of the offline-gated, debounced network catch-up.
          await ReadListReadingService.shared.refreshSnapshot()

          if authViewModel.bootstrapState == .requiresValidation {
            let serverReachable = await authViewModel.loadCurrentUser()
            if serverReachable {
              AppConfig.exitOfflineMode()
            } else {
              // No-op if we were already in manual offline mode (`enterAutoOfflineMode`
              // is guarded against converting manual → auto).
              AppConfig.enterAutoOfflineMode()
            }
          }

          guard isLoggedIn else { return }

          if enableSSE && !isOffline {
            await SSEService.shared.connect()
          }
          await ExternalContentSurfaceService.refreshWidgetsForCurrentInstance()

          // Wire automatic recovery from auto-entered offline mode. The
          // primary mechanism is `OfflineRecoveryService`'s backoff probe
          // loop, which runs while in auto-offline mode and probes the
          // configured server periodically. `NWPathMonitor` is used as an
          // opportunistic wake-up signal (skip the current backoff when the
          // device network state changes) — it cannot serve as the primary
          // trigger because the device network is typically still satisfied
          // during a server-side outage.
          //
          // All three are idempotent: re-fires on login state changes simply
          // replace the closures and (re)start the loop where applicable.
          OfflineRecoveryService.shared.probe = {
            await attemptAutoOfflineRecovery()
          }
          NetworkPathMonitorService.shared.onPathBecameSatisfied = {
            guard AppConfig.isOffline, AppConfig.offlineWasAutomatic else { return }
            OfflineRecoveryService.shared.wakeNow()
          }
          NetworkPathMonitorService.shared.start()

          // If we are already in auto-offline at the time the user logs in
          // (e.g., bootstrap probe just failed, or migration classified a
          // persisted offline state as auto), begin the recovery loop now so
          // we are not waiting on a network or scene transition to trigger it.
          if AppConfig.isOffline, AppConfig.offlineWasAutomatic {
            OfflineRecoveryService.shared.startIfNeeded()
          }
        }
        .task(id: automaticReadingHistorySyncTrigger) {
          guard !automaticReadingHistorySyncTrigger.isEmpty else { return }
          await syncViewModel.syncReadingProgressOnForeground()
        }
        .onChange(of: isOffline) { oldValue, newValue in
          if oldValue && !newValue {
            // Just came back online - sync pending progress and resume downloads
            Task {
              // Re-establish SSE after auto-offline recovery; without this the
              // connection stays down until the next foreground transition.
              if enableSSE {
                await SSEService.shared.connect()
              }
              await ProgressSyncService.shared.syncPendingProgress(
                instanceId: AppConfig.current.instanceId
              )
              // Pull the converged post-push state: replayed non-completed
              // progress is not re-fetched by the push itself.
              await syncViewModel.syncReadingProgressOnly(
                force: true, showsCompletionNotice: false)
              // Resume offline downloads
              if !AppConfig.offlinePaused {
                OfflineManager.shared.triggerSync(
                  instanceId: AppConfig.current.instanceId, restart: true)
              }
            }
            // Loop may still be running if the exit was driven by a non-probe
            // path (login flow, manual reconnect). Stop it explicitly so no
            // further wake-ups can spawn a stray probe.
            OfflineRecoveryService.shared.stop()
          }
          if !oldValue && newValue && AppConfig.offlineWasAutomatic {
            // Just entered auto-offline (e.g., `APIClient.handleNetworkError`
            // fired). Begin the recovery probe loop so we are not waiting on
            // an external trigger to start probing the server.
            OfflineRecoveryService.shared.startIfNeeded()
          }
        }
        .onChange(of: scenePhase) { oldPhase, phase in
          if phase == .active {
            let shouldReauthenticate = shouldReauthenticateProtectedCurrentInstance
            if shouldReauthenticate {
              protectedAccessGate = .checking
            }

            withAnimation(.easeInOut(duration: 0.2)) {
              showPrivacyBlur = false
            }

            // Wake the recovery loop if we're in auto-offline. Catches the
            // case where the loop's `Task.sleep` was deferred by iOS while
            // the app was suspended, or where a path-monitor transition fired
            // during suspension and was missed.
            if AppConfig.isOffline, AppConfig.offlineWasAutomatic {
              OfflineRecoveryService.shared.wakeNow()
            }
            Task {
              if shouldReauthenticate {
                guard await unlockProtectedCurrentInstanceForRendering() else { return }
              } else {
                guard hasRenderableAccessForCurrentInstance else { return }
              }

              if let database = await DatabaseOperator.databaseIfConfigured() {
                await database.updateInstanceLastUsed(instanceId: AppConfig.current.instanceId)
              }
              // Resume offline downloads if not paused and online
              if !AppConfig.isOffline && !AppConfig.offlinePaused {
                OfflineManager.shared.triggerSync(
                  instanceId: AppConfig.current.instanceId, restart: true)
              }
              // Push any offline-queued progress first so the pull below
              // observes the converged server state.
              await ProgressSyncService.shared.syncPendingProgress(
                instanceId: AppConfig.current.instanceId
              )
              await syncViewModel.syncReadingProgressOnForeground()

              if enableSSE && !isOffline {
                await SSEService.shared.connect()
              }
            }
          } else if phase == .inactive {
            // Lift the mask as soon as the app starts coming forward so the
            // snapshot cross-fade reveals live content. Skip when
            // reauthentication is due — content is only swapped for the
            // splash at .active.
            if oldPhase == .background && !shouldReauthenticateProtectedCurrentInstance {
              withAnimation(.easeInOut(duration: 0.2)) {
                showPrivacyBlur = false
              }
            }
          } else if phase == .background {
            // Mask only on real backgrounding, not .inactive, so the
            // swipe-to-switcher gesture keeps showing live content. No
            // fade-in here: the switcher snapshot is taken while the
            // animation is still running and would capture the mask
            // mid-fade, leaving content visible in the card.
            if privacyProtection {
              showPrivacyBlur = true
            }
            Task(priority: .utility) {
              await SSEService.shared.disconnect(notify: false)
              await ExternalContentSurfaceService.refreshWidgetsForCurrentInstance()
            }
          }
        }
      } else {
        LandingView(authViewModel: authViewModel)
          .onAppear {
            OfflineRecoveryService.shared.stop()
            OfflineRecoveryService.shared.probe = nil
            NetworkPathMonitorService.shared.onPathBecameSatisfied = nil
            Task {
              await SSEService.shared.disconnect(notify: false)
            }
          }
      }
    }
    #if os(iOS) || os(tvOS)
      .environment(\.zoomNamespace, zoomNamespace)
      .overlay {
        ReaderOverlay(namespace: zoomNamespace, readerPresentation: readerPresentation)
      }
    #endif
    #if os(iOS) || os(tvOS)
      .overlay(alignment: .bottom) {
        NotificationOverlay()
      }
    #endif
    .overlay {
      if showPrivacyBlur {
        Rectangle()
          .fill(.ultraThinMaterial)
          .ignoresSafeArea()
      }
    }
  }

  /// Probe the configured Komga server and exit offline mode on success, but
  /// only when we are in auto-entered offline mode. Manually-entered offline
  /// mode is preserved (the user explicitly opted in; only an explicit user
  /// action exits it).
  ///
  /// Invoked as the probe closure for `OfflineRecoveryService`, which calls
  /// it from a backoff loop while we are in auto-offline mode and also wakes
  /// it on `NWPathMonitor` path-satisfied signals and `scenePhase == .active`.
  ///
  /// Returns `.recovered` iff this call transitioned the app from offline →
  /// online. Returns `.retry` when the server is still unreachable, and `.stop`
  /// when recovery is no longer eligible.
  ///
  /// On successful exit, mirrors what `DashboardView.tryReconnect` does so
  /// the auto and manual recovery paths converge on identical post-recovery
  /// state.
  private func attemptAutoOfflineRecovery() async -> OfflineRecoveryService.ProbeResult {
    guard isLoggedIn else { return .stop }
    guard AppConfig.isOffline, AppConfig.offlineWasAutomatic else { return .stop }

    let reachable = await authViewModel.loadCurrentUser()

    // Re-check before mutating state:
    // - `loadCurrentUser` returns `true` even on `.unauthorized` (it calls
    //   `logout()` and returns `true` to signal "server reachable, just not
    //   authorized"). We must not treat that as a successful recovery —
    //   otherwise we'd fire a misleading "connection restored" notification
    //   while the user has actually been logged out. Re-checking `isLoggedIn`
    //   here is the guard.
    // - `AppConfig.isOffline` may have flipped false from another recovery path
    //   while this probe was in flight. Re-checking ensures only one caller
    //   fires the user-visible side effects (notification, SSE reconnect).
    guard AppConfig.isLoggedIn else { return .stop }
    guard AppConfig.isOffline, AppConfig.offlineWasAutomatic else { return .stop }
    guard reachable else { return .retry }

    AppConfig.exitOfflineMode()
    if enableSSE {
      await SSEService.shared.connect()
    }
    ErrorManager.shared.notify(
      message: String(localized: "settings.connection_restored")
    )
    // `ContentView.onChange(of: isOffline)` handles `syncPendingProgress` and
    // `triggerSync` for offline downloads once the flag transitions back to
    // online; nothing else to do here.
    return .recovered
  }

  private func unlockProtectedCurrentInstanceForRendering() async -> Bool {
    guard isLoggedIn else {
      protectedAccessGate = .checking
      return false
    }

    let instanceId = current.instanceId
    protectedAccessGate = .checking

    guard !instanceId.isEmpty else {
      protectedAccessGate = .unlocked(instanceId: instanceId, protected: false)
      return true
    }

    let result = await authenticateProtectedCurrentInstanceIfNeeded(instanceId: instanceId)
    guard result.authenticated else { return false }
    guard isLoggedIn, current.instanceId == instanceId else { return false }

    protectedAccessGate = .unlocked(instanceId: instanceId, protected: result.protected)
    return true
  }

  private func authenticateProtectedCurrentInstanceIfNeeded(
    instanceId: String
  ) async -> (authenticated: Bool, protected: Bool) {
    guard isLoggedIn, !instanceId.isEmpty else { return (true, false) }

    do {
      let database = try await DatabaseOperator.database()
      let protected = try await database.isServerProtected(instanceId: instanceId)
      guard protected else { return (true, false) }

      let authenticated = await LocalDeviceAuthenticationService.shared.authenticateProtectedAccess(
        reason: String(localized: "Authenticate to unlock this protected server.")
      )
      guard authenticated else {
        authViewModel.logout(clearCurrent: true)
        return (false, true)
      }

      return (true, true)
    } catch {
      ErrorManager.shared.alert(error: error)
      authViewModel.logout(clearCurrent: true)
      return (false, true)
    }
  }
}
