//
// ServerTasksView.swift
//
//

import SwiftUI

/// Live task queue (SSE) plus per-type execution metrics. kmrs answers the
/// metrics from `/api/v1/stats/server` in one request; elsewhere (Komga) the
/// `komga.tasks.*` actuator meters carry the same numbers per type.
struct ServerTasksView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("taskQueueStatus") private var taskQueueStatus: TaskQueueSSEDto = TaskQueueSSEDto()

  @State private var displayedTaskQueueStatus = TaskQueueSSEDto()
  @State private var taskMetrics: [TaskTypeMetrics] = []
  @State private var isLoading = false
  @State private var isCancelling = false
  @State private var showCancelAllConfirmation = false
  @State private var isLiveDotPulsing = false

  var body: some View {
    Form {
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
            ForEach(queuedTaskTypes, id: \.self) { taskType in
              HStack {
                Label(Self.taskTypeLabel(taskType), systemImage: "gearshape")
                  .font(.subheadline)
                Spacer()
                Text("\(displayedTaskQueueStatus.countByType[taskType] ?? 0)")
                  .fontWeight(.semibold)
                  .contentTransition(.numericText())
              }
              .padding(.vertical, 2)
              .tvFocusableHighlight()
            }
          }

          Divider()

          Button(role: .destructive) {
            showCancelAllConfirmation = true
          } label: {
            HStack {
              Spacer()
              if isCancelling {
                ProgressView()
              } else {
                Label(String(localized: "Cancel All Tasks"), systemImage: "xmark.circle")
              }
              Spacer()
            }
          }
          .adaptiveButtonStyle(.borderedProminent)
          .disabled(isCancelling || isLoading || displayedTaskQueueStatus.count == 0)
        }
        .padding(.vertical, 8)
      } header: {
        HStack {
          Text(String(localized: "Task Queue"))
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

      if !taskMetrics.isEmpty {
        Section(header: Text(String(localized: "Tasks Executed"))) {
          ForEach(taskMetrics) { task in
            VStack(alignment: .leading, spacing: 4) {
              Text(Self.taskTypeLabel(task.type))
                .font(.subheadline)
              HStack(spacing: 4) {
                Text(
                  String.localizedStringWithFormat(
                    String(localized: "server.tasks.runs", defaultValue: "%lld runs"),
                    Int(task.executions))
                )
                Text("·")
                Text(
                  String.localizedStringWithFormat(
                    String(localized: "server.tasks.totalTime", defaultValue: "%@ total"),
                    Self.formatTaskDuration(seconds: task.totalSeconds))
                )
                Text("·")
                Text(
                  String.localizedStringWithFormat(
                    String(localized: "server.tasks.longest", defaultValue: "%@ longest"),
                    Self.formatTaskDuration(seconds: task.maxSeconds))
                )
                if task.failures > 0 {
                  Text("·")
                  Text(
                    String.localizedStringWithFormat(
                      String(localized: "%lld failed"),
                      Int(task.failures))
                  )
                  .foregroundColor(.red)
                }
              }
              .font(.caption)
              .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            .tvFocusableHighlight()
          }
        }
      } else if !isLoading {
        Section(header: Text(String(localized: "Tasks Executed"))) {
          Text(String(localized: "No tasks executed yet."))
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "Tasks"))
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
      withAnimation {
        displayedTaskQueueStatus = taskQueueStatus
      }
      await loadTaskMetrics()
    }
    .onChange(of: taskQueueStatus) { _, newValue in
      withAnimation {
        displayedTaskQueueStatus = newValue
      }
    }
    .refreshable {
      await loadTaskMetrics()
    }
  }

  private var queuedTaskTypes: [String] {
    displayedTaskQueueStatus.countByType.keys.sorted()
  }

  static func taskTypeLabel(_ type: String) -> String {
    let words = type.replacingOccurrences(
      of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
    return words.prefix(1).uppercased() + words.dropFirst().lowercased()
  }

  static func formatTaskDuration(seconds: Double) -> String {
    if seconds < 1 {
      return "\(Int(seconds * 1000)) ms"
    }
    return ServerInfoView.formatDuration(seconds: seconds)
  }

  private func loadTaskMetrics() async {
    // The queue display works offline from the persisted SSE snapshot.
    guard !AppConfig.isOffline else { return }
    isLoading = true

    do {
      if let stats = try await ServerStatsService.getServerStatsIfSupported(
        instanceId: current.instanceId)
      {
        taskMetrics = Self.metrics(from: stats)
      } else {
        await loadActuatorTaskMetrics()
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }

    isLoading = false
  }

  /// Komga path: the type list comes from the untagged meter's available
  /// tags, then each type's timer and failure counter are queried by tag.
  private func loadActuatorTaskMetrics() async {
    do {
      guard
        let execution = try await ManagementService.getMetricOptional("komga.tasks.execution"),
        let types = execution.availableTags?.first(where: { $0.tag == "type" })?.values,
        !types.isEmpty
      else {
        taskMetrics = []
        return
      }

      let loaded = try await withThrowingTaskGroup(of: TaskTypeMetrics.self) { group in
        for type in types {
          group.addTask {
            async let executionRequest = ManagementService.getMetricOptional(
              "komga.tasks.execution", tags: [MetricTag(key: "type", value: type)])
            async let failureRequest = ManagementService.getMetricOptional(
              "komga.tasks.failure", tags: [MetricTag(key: "type", value: type)])
            let (execution, failure) = try await (executionRequest, failureRequest)
            return TaskTypeMetrics(
              type: type,
              executions: execution?.value("COUNT") ?? 0,
              totalSeconds: execution?.value("TOTAL_TIME") ?? 0,
              maxSeconds: execution?.value("MAX") ?? 0,
              failures: failure?.value("COUNT") ?? 0
            )
          }
        }
        var result: [TaskTypeMetrics] = []
        for try await metric in group {
          result.append(metric)
        }
        return result
      }
      taskMetrics = Self.sorted(loaded)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  private static func metrics(from stats: ServerStatsResponse) -> [TaskTypeMetrics] {
    sorted(
      stats.tasks.types.map { task in
        TaskTypeMetrics(
          type: task.type,
          executions: task.executions,
          totalSeconds: task.totalTimeMs / 1000,
          maxSeconds: task.maxTimeMs / 1000,
          failures: task.failures
        )
      })
  }

  private static func sorted(_ metrics: [TaskTypeMetrics]) -> [TaskTypeMetrics] {
    metrics.filter { $0.executions > 0 }
      .sorted { $0.executions > $1.executions }
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
        await loadTaskMetrics()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      withAnimation {
        isCancelling = false
      }
    }
  }

  nonisolated struct TaskTypeMetrics: Identifiable, Sendable {
    let type: String
    let executions: Double
    let totalSeconds: Double
    let maxSeconds: Double
    let failures: Double

    var id: String { type }
  }
}
