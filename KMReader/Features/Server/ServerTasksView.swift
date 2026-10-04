//
// ServerTasksView.swift
//
//

import SwiftUI

struct ServerTasksView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("taskQueueStatus") private var taskQueueStatus: TaskQueueSSEDto = TaskQueueSSEDto()

  @State private var displayedTaskQueueStatus = TaskQueueSSEDto()
  @State private var isLoading = false
  @State private var isCancelling = false
  @State private var showCancelAllConfirmation = false
  @State private var hasLoadedMetrics = false
  @State private var isLiveDotPulsing = false

  // Tasks metrics
  @State private var tasks: Metric?
  @State private var tasksCountByType: [String: Double] = [:]
  @State private var tasksTotalTimeByType: [String: Double] = [:]
  @State private var metricErrors: [TaskErrorKey: String] = [:]

  var body: some View {
    Form {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading && !hasLoadedMetrics {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else {
        #if os(tvOS) || os(macOS)
          if current.isAdmin {
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
          }
        #endif

        // Task Queue Status Section (from SSE)
        if displayedTaskQueueStatus.count > 0 {
          Section {
            VStack(spacing: 12) {
              // Total Tasks with highlight
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

              // Task types with animation
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

        // Tasks Section
        if !tasksCountByType.isEmpty || metricErrors[.tasksExecuted] != nil {
          Section(header: Text(String(localized: "Tasks Executed"))) {
            ForEach(Array(tasksCountByType.keys.sorted()), id: \.self) { taskType in
              if let count = tasksCountByType[taskType] {
                HStack {
                  Label(taskType, systemImage: "gearshape")
                  Spacer()
                  Text("\(Int(count))")
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }
            if let error = metricErrors[.tasksExecuted] {
              HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundColor(.orange)
                Text(error)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
          }
        }

        if !tasksTotalTimeByType.isEmpty || metricErrors[.tasksTotalTime] != nil {
          Section(header: Text(String(localized: "Tasks Total Time"))) {
            ForEach(Array(tasksTotalTimeByType.keys.sorted()), id: \.self) { taskType in
              if let time = tasksTotalTimeByType[taskType] {
                HStack {
                  Label(taskType, systemImage: "clock")
                  Spacer()
                  Text(String(format: "%.2f s", time))
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }
            if let error = metricErrors[.tasksTotalTime] {
              HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundColor(.orange)
                Text(error)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(ServerSection.tasks.title)
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
        await loadMetrics()
      }
    }
    .onChange(of: taskQueueStatus) { _, newValue in
      withAnimation {
        displayedTaskQueueStatus = newValue
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadMetrics()
      }
    }
  }

  private func loadMetrics() async {
    if !hasLoadedMetrics {
      withAnimation {
        isLoading = true
      }
    }
    withAnimation {
      metricErrors.removeAll()
    }

    // Load tasks metrics
    do {
      let metric = try await ManagementService.getMetric(MetricName.tasksExecution.rawValue)
      let (countByType, totalTimeByType, errors) = await processTasksMetrics(metric)

      withAnimation {
        tasks = metric
        tasksCountByType = countByType
        tasksTotalTimeByType = totalTimeByType
        if let tasksExecutedError = errors[.tasksExecuted] {
          metricErrors[.tasksExecuted] = tasksExecutedError
        }
        if let tasksTotalTimeError = errors[.tasksTotalTime] {
          metricErrors[.tasksTotalTime] = tasksTotalTimeError
        }
      }
    } catch {
      withAnimation {
        tasks = nil
      }
    }

    withAnimation {
      hasLoadedMetrics = true
      isLoading = false
    }
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
        await loadMetrics()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      withAnimation {
        isCancelling = false
      }
    }
  }

  private func processTasksMetrics(_ metric: Metric) async -> (
    [String: Double], [String: Double], [TaskErrorKey: String]
  ) {
    var countByType: [String: Double] = [:]
    var totalTimeByType: [String: Double] = [:]
    var errors: [TaskErrorKey: String] = [:]
    var countErrorCount = 0
    var timeErrorCount = 0

    guard let typeTag = metric.availableTags?.first(where: { $0.tag == "type" }) else {
      return (countByType, totalTimeByType, errors)
    }

    for taskType in typeTag.values {
      do {
        let taskMetric = try await ManagementService.getMetric(
          metric.name, tags: [MetricTag(key: "type", value: taskType)])

        if let count = taskMetric.measurements.first(where: { $0.statistic == "COUNT" })?.value {
          countByType[taskType] = count
        } else {
          countErrorCount += 1
        }
        if let totalTime = taskMetric.measurements.first(where: { $0.statistic == "TOTAL_TIME" })?
          .value
        {
          totalTimeByType[taskType] = totalTime
        } else {
          timeErrorCount += 1
        }
      } catch {
        // Track errors for individual task types
        countErrorCount += 1
        timeErrorCount += 1
        continue
      }
    }

    if countErrorCount > 0 {
      errors[.tasksExecuted] =
        "Failed to load count metrics for \(countErrorCount) task type\(countErrorCount == 1 ? "" : "s")"
    }
    if timeErrorCount > 0 {
      errors[.tasksTotalTime] =
        "Failed to load time metrics for \(timeErrorCount) task type\(timeErrorCount == 1 ? "" : "s")"
    }

    return (countByType, totalTimeByType, errors)
  }
}

// MARK: - Data Structures

enum TaskErrorKey: Hashable {
  case tasksExecuted
  case tasksTotalTime
}
