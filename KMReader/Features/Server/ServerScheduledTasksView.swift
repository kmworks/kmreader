//
// ServerScheduledTasksView.swift
//
//

import SwiftUI

/// Fixed-rate scheduled tasks from `/actuator/scheduledtasks` (admin only):
/// the per-library scan intervals plus the daily maintenance jobs.
struct ServerScheduledTasksView: View {
  @State private var tasks: [ActuatorScheduledTasksResponse.ScheduledTask] = []
  @State private var isLoading = false
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
        } else if tasks.isEmpty {
          ContentUnavailableView {
            Label(String(localized: "No Scheduled Tasks"), systemImage: "calendar.badge.clock")
          } description: {
            Text(String(localized: "The server has no scheduled tasks."))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        } else {
          ForEach(tasks) { task in
            HStack {
              Text(Self.targetLabel(task.runnable.target))
                .font(.subheadline)
              Spacer()
              Text(Self.formatInterval(ms: task.interval))
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            .tvFocusableHighlight()
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "Scheduled Tasks"))
    .task {
      await loadTasks()
    }
    .refreshable {
      await loadTasks()
    }
  }

  private static func formatInterval(ms: Double) -> String {
    Duration.milliseconds(ms)
      .formatted(
        .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1)
      )
  }

  /// Komga reports Java FQN/lambda targets; keep the meaningful tail.
  private static func targetLabel(_ target: String) -> String {
    let cleaned = target.components(separatedBy: "$").first ?? target
    let parts = cleaned.split(separator: ".", omittingEmptySubsequences: true)
    return parts.count >= 3 ? parts.suffix(2).joined(separator: ".") : cleaned
  }

  private func loadTasks() async {
    isLoading = true
    do {
      tasks = try await ManagementService.getScheduledTasks().fixedRate
      hasLoaded = true
    } catch {
      ErrorManager.shared.alert(error: error)
    }
    isLoading = false
  }
}
