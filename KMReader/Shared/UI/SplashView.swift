//
// SplashView.swift
//
//

import SwiftUI

struct SplashView: View {
  @State private var isVisible: Bool
  @State private var loadingMessageIndex = 0
  @State private var pulseProgress = 1.0
  @State private var messageRotationTask: Task<Void, Never>?

  let syncViewModel: SyncViewModel?
  let isMigration: Bool
  let enterOfflineMode: (() -> Void)?

  init(
    syncViewModel: SyncViewModel? = nil,
    isMigration: Bool = false,
    enterOfflineMode: (() -> Void)? = nil
  ) {
    self.syncViewModel = syncViewModel
    self.isMigration = isMigration
    self.enterOfflineMode = enterOfflineMode
    _isVisible = State(initialValue: isMigration)
  }

  private var loadingMessages: [String] {
    if isMigration {
      [
        String(
          localized: "splash.migration.preparing",
          defaultValue: "Preparing local database migration"
        ),
        String(
          localized: "splash.migration.migrating",
          defaultValue: "Migrating existing local data"
        ),
        String(
          localized: "splash.migration.finalizing",
          defaultValue: "Finalizing local data migration"
        ),
      ]
    } else {
      [
        String(localized: "splash.loading.connecting"),
        String(localized: "splash.loading.syncing"),
        String(localized: "splash.loading.updating"),
        String(localized: "splash.loading.preparing"),
      ]
    }
  }

  private var isSyncing: Bool {
    syncViewModel?.isSyncing ?? false
  }

  private var syncStages: [SyncStage] {
    syncViewModel?.visibleStages ?? SyncStage.visibleStages(includeReconcile: false)
  }

  private var includesReconcileStages: Bool {
    syncViewModel?.includesReconcileStages ?? false
  }

  private func stageProgress(for stage: SyncStage) -> Double {
    syncViewModel?.progress(for: stage) ?? 0.0
  }

  private func stageTextStyle(for stage: SyncStage) -> AnyShapeStyle {
    let progress = stageProgress(for: stage)
    return AnyShapeStyle((progress > 0.0 && progress < 1.0) ? .primary : .secondary)
  }

  var body: some View {
    VStack(spacing: 32) {
      Spacer()

      VStack(spacing: 16) {
        // Logo with animation
        Image(AppIconLogoAsset.current)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(height: 140)
          .scaleEffect(isVisible ? 1.0 : 0.8)
          .opacity(isVisible ? 1.0 : 0.0)

        // App Name
        Text("KMReader")
          .font(.largeTitle.weight(.bold))
          .fontDesign(.rounded)
          .foregroundStyle(.primary)
          .tracking(1.2)
          .offset(y: isVisible ? 0 : 20)
          .opacity(isVisible ? 1.0 : 0.0)

        // Tagline
        Text("Your Komga library, ready to read")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .tracking(0.5)
          .offset(y: isVisible ? 0 : 20)
          .opacity(isVisible ? 0.8 : 0.0)
      }

      Spacer()

      VStack(spacing: 16) {
        if isSyncing {
          // Stage-based progress bars during initialization
          VStack(alignment: .leading, spacing: 10) {
            ForEach(syncStages, id: \.self) { stage in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(stage.localizedName(includeReconcile: includesReconcileStages))
                    .font(.caption)
                    .foregroundStyle(stageTextStyle(for: stage))
                  Spacer()
                  Text(stageProgress(for: stage), format: .percent.precision(.fractionLength(0)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                }

                ProgressView(value: stageProgress(for: stage))
                  .progressViewStyle(.linear)
              }
            }
          }
          .frame(maxWidth: 320)
          .opacity(isVisible ? 1.0 : 0.0)
        } else {
          // Indeterminate spinner when not initializing
          ProgressView()
            .controlSize(.large)
            .scaleEffect(pulseProgress)
            .opacity(isVisible ? 1.0 : 0.0)

          Text(loadingMessages[loadingMessageIndex])
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .transition(
              .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity))
            )
            .id(loadingMessageIndex)

          if isMigration {
            Text(
              String(
                localized: "splash.migration.duration_hint",
                defaultValue:
                  "Large libraries may take 1-2 minutes to migrate. Please keep KMReader open."
              )
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
          } else if let enterOfflineMode {
            Button {
              enterOfflineMode()
            } label: {
              Label(
                String(
                  localized: "splash.offline.enter",
                  defaultValue: "Enter Offline Mode"
                ),
                systemImage: "wifi.slash"
              )
              .font(.caption)
            }
            .controlSize(.small)
            .adaptiveButtonStyle(.bordered)
          }
        }
      }

      Spacer()
        .frame(height: 60)
    }
    .onAppear {
      if !isVisible {
        withAnimation(.appSpring) {
          isVisible = true
        }
      }

      // Pulse animation for ProgressView
      withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
        pulseProgress = 1.1
      }

      // Rotate loading messages
      messageRotationTask?.cancel()
      messageRotationTask = Task {
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          withAnimation(.appCurve(0.5)) {
            loadingMessageIndex = (loadingMessageIndex + 1) % loadingMessages.count
          }
        }
      }
    }
    .onDisappear {
      messageRotationTask?.cancel()
      messageRotationTask = nil
    }
  }
}

#Preview {
  SplashView()
}

#Preview("Migrating") {
  SplashView(isMigration: true)
}

#Preview("Initializing") {
  SplashView(syncViewModel: SyncViewModel.shared)
}
