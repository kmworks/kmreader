//
//  KMReaderWidgetsLiveActivity.swift
//  KMReaderWidgets
//
//  Created by Chuan Chuan on 2025/12/23.
//

import SwiftUI
import WidgetKit

#if os(iOS)
  import ActivityKit

  struct KMReaderWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
      ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
        // Lock screen/banner UI
        VStack(spacing: 8) {
          // Header with series info
          HStack {
            Image(systemName: "arrow.down.circle.fill")
              .font(.title2)
              .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
              if let seriesTitle = context.state.displaySeriesTitle {
                Text(seriesTitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }

              Text(context.state.bookInfo)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            }

            Spacer()

            // Progress percentage
            if context.state.progress > 0 {
              Text("\(Int(context.state.progress * 100))%")
                .font(.title3.weight(.bold))
                .foregroundStyle(.blue)
                .monospacedDigit()
            } else {
              ProgressView()
                .tint(.blue)
            }
          }

          // Progress bar
          progressBar(for: context.state)

          // Footer stats
          if context.state.pendingCount > 0 || context.state.failedCount > 0 {
            HStack {
              if context.state.pendingCount > 0 {
                Label("\(context.state.pendingCount)", systemImage: "clock")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }

              Spacer()

              if context.state.failedCount > 0 {
                Label("\(context.state.failedCount)", systemImage: "exclamationmark.triangle.fill")
                  .font(.caption2)
                  .foregroundStyle(.red)
              }
            }
            .padding(.horizontal, 4)
          }
        }
        .padding(12)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.95))
        .activitySystemActionForegroundColor(.primary)

      } dynamicIsland: { context in
        DynamicIsland {
          // Expanded UI
          DynamicIslandExpandedRegion(.leading) {
            HStack(spacing: 0) {
              Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .font(.title2)
              Spacer(minLength: 0)
            }
            .padding(.leading, 12)
          }
          DynamicIslandExpandedRegion(.trailing) {
            HStack(spacing: 0) {
              Spacer(minLength: 0)
              if context.state.progress > 0 {
                Text("\(Int(context.state.progress * 100))%")
                  .font(.headline.weight(.bold))
                  .foregroundStyle(.blue)
                  .monospacedDigit()
              } else {
                Image(systemName: "ellipsis")
                  .font(.headline.weight(.bold))
                  .foregroundStyle(.blue)
              }
            }
            .padding(.trailing, 12)
          }
          DynamicIslandExpandedRegion(.center) {
            VStack(spacing: 2) {
              if let seriesTitle = context.state.displaySeriesTitle {
                Text(seriesTitle)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Text(context.state.bookInfo)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            }
          }
          DynamicIslandExpandedRegion(.bottom) {
            progressBar(for: context.state)
          }
        } compactLeading: {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(.blue)
        } compactTrailing: {
          if context.state.progress > 0 {
            Text("\(Int(context.state.progress * 100))%")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.blue)
              .monospacedDigit()
          } else {
            Image(systemName: "ellipsis")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.blue)
          }
        } minimal: {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(.blue)
        }
        .keylineTint(.blue)
      }
    }
  }

  extension DownloadActivityAttributes {
    fileprivate static var preview: DownloadActivityAttributes {
      DownloadActivityAttributes(totalBooks: 5)
    }
  }

  extension DownloadActivityAttributes.ContentState {
    fileprivate var displaySeriesTitle: String? {
      guard let seriesTitle, !seriesTitle.isEmpty else { return nil }
      return seriesTitle
    }

    fileprivate var progressFraction: Double {
      min(max(progress, 0), 1)
    }

    fileprivate static var downloading: DownloadActivityAttributes.ContentState {
      DownloadActivityAttributes.ContentState(
        seriesTitle: "One Piece",
        bookInfo: "#1058 - The Flame Emperor's Triumph",
        progress: 0.65,
        pendingCount: 12,
        failedCount: 1
      )
    }
  }

  #Preview("Notification", as: .content, using: DownloadActivityAttributes.preview) {
    KMReaderWidgetsLiveActivity()
  } contentStates: {
    DownloadActivityAttributes.ContentState.downloading
  }

  extension KMReaderWidgetsLiveActivity {
    private func progressBar(for state: DownloadActivityAttributes.ContentState) -> some View {
      Capsule()
        .fill(Color.secondary.opacity(0.2))
        .frame(height: 6)
        .overlay {
          GeometryReader { geometry in
            HStack {
              Capsule()
                .fill(
                  LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                  )
                )
                .frame(width: geometry.size.width * state.progressFraction, height: 6)
              Spacer(minLength: 0)
            }
          }
        }
        .animation(.easeInOut(duration: 0.25), value: state.progressFraction)
    }
  }
#endif
