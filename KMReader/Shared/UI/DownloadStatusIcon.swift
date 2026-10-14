//
// DownloadStatusIcon.swift
//
//

import SwiftUI

struct DownloadStatusIcon: View {
  let systemName: String
  let spinning: Bool
  var color: Color = .secondary
  /// Book-level downloads get a live progress pie while spinning; a pending book
  /// with no tracker entry yet is queued and gets the hourglass. Aggregate
  /// (series/read-list) statuses have no single progress and keep the spinner.
  var bookId: String? = nil

  /// Downloaded-state glyph, shared with DownloadStatus.displayIcon.
  private static let downloadedSystemName = AppIcon.downloaded
  /// Drawn check and settle bounce, overlapping; total 0.31s.
  private static let completionDuration: TimeInterval = 0.31

  /// Status changes are held back while the completion check plays, so the full
  /// checkmark is always visible before the icon can switch away.
  @State private var displayedSystemName: String?
  @State private var displayedSpinning: Bool?
  @State private var isCompleting = false
  @State private var checkProgress: Double = 0
  @State private var bounceTrigger = 0
  @State private var progressTracker = DownloadProgressTracker.shared
  /// The tracker entry is cleared at completion while the status flip is still
  /// in flight; the last reported value keeps the pie full until the completion
  /// checkmark replaces it. Reset when spinning stops so a re-queued download
  /// falls back to the queued glyph instead of a stale pie.
  @State private var lastReportedProgress: Double = 0

  private var effectiveSystemName: String {
    displayedSystemName ?? systemName
  }

  private var effectiveSpinning: Bool {
    displayedSpinning ?? spinning
  }

  var body: some View {
    Group {
      if isCompleting {
        // The hidden glyph keeps the frame identical to the settled icon's.
        Image(systemName: Self.downloadedSystemName)
          .hidden()
          .overlay {
            DownloadCompletionCheckmark(
              progress: checkProgress, color: color, bounceTrigger: bounceTrigger)
          }
          .transition(.opacity)
      } else if effectiveSpinning {
        if let bookId {
          if progressTracker.progress[bookId] != nil || lastReportedProgress > 0 {
            Image(systemName: systemName)
              .hidden()
              .overlay {
                DownloadProgressPie(
                  progress: progressTracker.progress[bookId] ?? lastReportedProgress,
                  color: color
                )
              }
              .transition(.opacity)
          } else {
            // The tracker only gets an entry once the download starts; before
            // that the book is queued and a 0 pie would read as in-flight.
            Image(systemName: AppIcon.downloadQueued)
              .foregroundColor(color)
              .transition(.opacity)
          }
        } else {
          spinningContent
            .transition(.opacity)
        }
      } else {
        Image(systemName: effectiveSystemName)
          .foregroundColor(color)
          .transition(.opacity)
      }
    }
    .animation(.appCurve(), value: effectiveSpinning)
    .animation(.appCurve(), value: isCompleting)
    .onAppear {
      displayedSystemName = systemName
      displayedSpinning = spinning
    }
    .onChange(of: systemName) { _, _ in handleStatusChange() }
    .onChange(of: spinning) { _, newValue in
      if !newValue { lastReportedProgress = 0 }
      handleStatusChange()
    }
    .onChange(of: progressTracker.progress) { _, newValue in
      if let bookId, let reported = newValue[bookId] {
        lastReportedProgress = reported
      }
    }
  }

  @ViewBuilder
  private var spinningContent: some View {
    if #available(iOS 18.0, macOS 15.0, tvOS 18.0, *) {
      Image(systemName: effectiveSystemName)
        .symbolEffect(.rotate)
        .foregroundColor(color)
    } else {
      // Older OSes get a real spinner: symbolEffect(.rotate) is iOS 18+.
      ProgressView()
        .controlSize(.mini)
        .tint(color)
    }
  }

  private func handleStatusChange() {
    guard displayedSystemName != nil, !isCompleting else { return }
    if systemName == Self.downloadedSystemName, displayedSystemName != Self.downloadedSystemName {
      beginCompletion()
    } else {
      displayedSystemName = systemName
      displayedSpinning = spinning
    }
  }

  private func beginCompletion() {
    isCompleting = true
    checkProgress = 0
    bounceTrigger += 1
    withAnimation(.linear(duration: 0.25)) {
      checkProgress = 1
    }
    Task {
      try? await Task.sleep(for: .seconds(Self.completionDuration))
      finishCompletion()
    }
  }

  private func finishCompletion() {
    isCompleting = false
    displayedSystemName = systemName
    displayedSpinning = spinning
  }
}
