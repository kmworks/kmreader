//
// ServerInfoView.swift
//
//

import SwiftUI

/// Server snapshot from the kmrs stats endpoints plus the SSE task queue
/// (which works on any server). Servers without the stats endpoints (Komga,
/// older kmrs) hide the stats sections and get the unavailable state when
/// there is nothing else to show.
struct ServerInfoView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("taskQueueStatus") private var taskQueueStatus: TaskQueueSSEDto = TaskQueueSSEDto()

  @State private var displayedTaskQueueStatus = TaskQueueSSEDto()
  @State private var stats: ServerStatsResponse?
  @State private var isLoading = false
  @State private var isUnsupported = false
  @State private var isCancelling = false
  @State private var showCancelAllConfirmation = false
  @State private var isLiveDotPulsing = false

  var body: some View {
    Form {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading && stats == nil && !isUnsupported {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else {
        #if os(tvOS) || os(macOS)
          Section {
            Button(role: .destructive) {
              withAnimation {
                showCancelAllConfirmation = true
              }
            } label: {
              HStack {
                Spacer()
                if isCancelling {
                  ProgressView()
                } else {
                  Label("Cancel All Tasks", systemImage: "xmark.circle")
                }
                Spacer()
              }
            }
            .adaptiveButtonStyle(.borderedProminent)
            .disabled(isCancelling || isLoading)
          }
          .listRowBackground(Color.clear)
        #endif

        if displayedTaskQueueStatus.count > 0 {
          Section {
            VStack(spacing: 12) {
              HStack {
                Label(String(localized: "Total Tasks"), systemImage: "list.bullet.clipboard")
                  .font(.headline)
                Spacer()
                Text("\(displayedTaskQueueStatus.count)")
                  .font(.title2)
                  .fontWeight(.bold)
                  .foregroundColor(
                    displayedTaskQueueStatus.count > 0 ? .primary : .secondary
                  )
                  .contentTransition(.numericText())
              }
              .padding(.vertical, 4)
              .tvFocusableHighlight()

              if !displayedTaskQueueStatus.countByType.isEmpty {
                Divider()
                ForEach(Array(displayedTaskQueueStatus.countByType.keys.sorted()), id: \.self) {
                  taskType in
                  if let count = displayedTaskQueueStatus.countByType[taskType] {
                    HStack {
                      Label(taskType, systemImage: "gearshape")
                        .font(.subheadline)
                      Spacer()
                      Text("\(count)")
                        .fontWeight(.semibold)
                        .foregroundColor(count > 0 ? .primary : .secondary)
                        .contentTransition(.numericText())
                    }
                    .padding(.vertical, 2)
                    .tvFocusableHighlight()
                  }
                }
              }
            }
            .padding(.vertical, 8)
          } header: {
            HStack {
              Text(String(localized: "Task Queue Status"))
                .font(.headline)
              Spacer()
              if displayedTaskQueueStatus.count > 0 {
                Circle()
                  .fill(Color.primary)
                  .frame(width: 8, height: 8)
                  .opacity(isLiveDotPulsing ? 0.25 : 1.0)
                  .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                      isLiveDotPulsing = true
                    }
                  }
              }
            }
          }
        }

        if isUnsupported {
          if displayedTaskQueueStatus.count == 0 {
            Section {
              ContentUnavailableView {
                Label(
                  String(localized: "Server Info Unavailable"),
                  systemImage: ServerSection.serverInfo.icon)
              } description: {
                Text(String(localized: "This server does not provide server statistics."))
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
            }
          }
        } else if let stats {
          Section(header: Text(String(localized: "Process"))) {
            if let startTime = Self.startTimeFormatter.date(from: stats.process.startTime) {
              infoRow(
                String(localized: "Start Time"),
                startTime.formatted(date: .abbreviated, time: .shortened),
                "clock")
            }
            infoRow(
              String(localized: "Uptime"),
              Duration.seconds(stats.process.uptimeSeconds)
                .formatted(
                  .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2)
                ),
              "timer")
            infoRow(
              String(localized: "CPU Usage"),
              String(format: "%.1f %%", stats.process.cpuUsage),
              "cpu")
            infoRow(
              String(localized: "Memory"),
              stats.process.memoryBytes.humanReadableFileSize,
              "memorychip")
          }

          Section(header: Text(String(localized: "Totals"))) {
            infoRow(String(localized: "Libraries"), "\(Int(stats.totals.libraries))", ContentIcon.library)
            infoRow(
              String(localized: "Collections"), "\(Int(stats.totals.collections))", ContentIcon.collection)
            infoRow(
              String(localized: "Read Lists"), "\(Int(stats.totals.readlists))", ContentIcon.readList)
            infoRow(
              String(localized: "Sidecars"), "\(Int(stats.totals.sidecars))", "doc.badge.gearshape")
          }

          if !executedTaskTypes.isEmpty {
            Section(header: Text(String(localized: "Tasks Executed"))) {
              ForEach(executedTaskTypes, id: \.type) { task in
                HStack {
                  Label(task.type, systemImage: "gearshape")
                  Spacer()
                  Text("\(Int(task.executions))")
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }

            Section(header: Text(String(localized: "Tasks Total Time"))) {
              ForEach(executedTaskTypes, id: \.type) { task in
                HStack {
                  Label(task.type, systemImage: "clock")
                  Spacer()
                  Text(String(format: "%.2f s", task.totalTimeMs / 1000))
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }
          }

          if !failedTaskTypes.isEmpty {
            Section(header: Text(String(localized: "Tasks Failed"))) {
              ForEach(failedTaskTypes, id: \.type) { task in
                HStack {
                  Label(task.type, systemImage: "gearshape")
                  Spacer()
                  Text("\(Int(task.failures))")
                    .foregroundColor(.red)
                }
                .tvFocusableHighlight()
              }
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(ServerSection.serverInfo.title)
    #if os(iOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(role: .destructive) {
            withAnimation {
              showCancelAllConfirmation = true
            }
          } label: {
            Label(String(localized: "Cancel All Tasks"), systemImage: "xmark.circle")
          }
          .disabled(isCancelling || isLoading)
        }
      }
    #endif
    .alert(String(localized: "Cancel All Tasks"), isPresented: $showCancelAllConfirmation) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Confirm"), role: .destructive) {
        cancelAllTasks()
      }
    } message: {
      Text(
        String(
          localized: "Are you sure you want to cancel all tasks? This action cannot be undone.")
      )
    }
    .task {
      if current.isAdmin {
        withAnimation {
          displayedTaskQueueStatus = taskQueueStatus
        }
        await loadServerStats()
      }
    }
    .onChange(of: taskQueueStatus) { _, newValue in
      withAnimation {
        displayedTaskQueueStatus = newValue
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadServerStats()
      }
    }
  }

  private var executedTaskTypes: [ServerStatsResponse.TaskTypeStats] {
    stats?.tasks.types.filter { $0.executions > 0 } ?? []
  }

  private var failedTaskTypes: [ServerStatsResponse.TaskTypeStats] {
    stats?.tasks.types.filter { $0.failures > 0 } ?? []
  }

  private static let startTimeFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private func infoRow(_ label: String, _ value: String, _ icon: String) -> some View {
    InfoRow(label: label, value: value, icon: icon)
      .tvFocusableHighlight()
  }

  private func loadServerStats() async {
    isLoading = true

    if ServerStatsService.shouldQueryServer(instanceId: current.instanceId) {
      do {
        let loaded = try await ServerStatsService.getServerStats()
        ServerStatsService.recordServerCapability(instanceId: current.instanceId, supported: true)
        stats = loaded
        isUnsupported = false
      } catch let error as APIError {
        if case .notFound = error {
          ServerStatsService.recordServerCapability(instanceId: current.instanceId, supported: false)
          isUnsupported = true
        } else {
          ErrorManager.shared.alert(error: error)
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    } else if !AppConfig.isOffline {
      isUnsupported = true
    }

    isLoading = false
  }

  private func cancelAllTasks() {
    guard !isCancelling else { return }
    withAnimation {
      isCancelling = true
    }
    Task {
      do {
        try await ManagementService.cancelAllTasks()
        ErrorManager.shared.notify(message: String(localized: "notification.tasks.cancelled"))
        await loadServerStats()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      withAnimation {
        isCancelling = false
      }
    }
  }
}
