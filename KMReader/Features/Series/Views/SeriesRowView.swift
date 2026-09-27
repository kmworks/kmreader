//
// SeriesRowView.swift
//
//

import SwiftUI

struct SeriesRowView: View {
  let item: SeriesDisplayItem
  var onMutationCompleted: (() -> Void)? = nil
  var onDeleteRequested: (() -> Void)? = nil

  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false

  @State private var showCollectionPicker = false
  @State private var showEditSheet = false

  var series: Series {
    item.series
  }

  var downloadStatus: SeriesDownloadStatus {
    item.downloadStatus
  }

  var progress: Double {
    guard item.booksCount > 0 else { return 0 }
    guard item.booksReadCount > 0 else { return 0 }
    return Double(item.booksReadCount) / Double(item.booksCount)
  }

  private var coverBlurRadius: CGFloat {
    thumbnailBlurUnreadCovers && item.isUnread ? CoverBlurStyle.unreadRadius : 0
  }

  var body: some View {
    HStack(spacing: 12) {
      NavigationLink(value: item.navDestination) {
        ThumbnailImage(
          id: series.id,
          type: .series,
          contentBlurRadius: coverBlurRadius,
          width: 80
        )
      }
      .adaptiveButtonStyle(.plain)

      VStack(alignment: .leading, spacing: 6) {
        NavigationLink(value: item.navDestination) {
          Text(series.metadata.title)
            .font(.callout)
            .lineLimit(2)
        }.adaptiveButtonStyle(.plain)

        HStack {
          VStack(alignment: .leading, spacing: 4) {
            if series.oneshot {
              Label(item.oneshotLine, systemImage: "book.closed")
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(1)
            } else {
              Label(series.statusDisplayName, systemImage: series.statusIcon)
                .font(.footnote)
                .foregroundColor(series.statusColor)
            }

            if let releaseDate = series.booksMetadata.releaseDate {
              Label("Release: \(releaseDate)", systemImage: "calendar")
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
              Label("Last Updated: \(series.lastUpdatedDisplay)", systemImage: "clock")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            HStack {
              if series.deleted {
                Text("Unavailable")
                  .foregroundColor(.red)
              } else {
                readingProgressSummary
              }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
          }

          Spacer()

          if let icon = downloadStatus.icon {
            DownloadStatusIcon(systemName: icon, spinning: downloadStatus.isPending)
          }
          EllipsisMenuButton {
            SeriesContextMenu(
              seriesId: item.seriesId,
              downloadStatus: item.downloadStatus,
              offlinePolicy: item.offlinePolicy,
              offlinePolicyLimit: item.offlinePolicyLimit,
              booksUnreadCount: item.booksUnreadCount,
              booksReadCount: item.booksReadCount,
              booksInProgressCount: item.booksInProgressCount,
              onShowCollectionPicker: {
                #if os(macOS)
                  // Present in a standalone window: a view-attached sheet
                  // triggered from an NSMenu action can wedge the app on
                  // macOS 15.
                  PickerWindowOpener.shared.open(.collection(seriesId: item.seriesId))
                #else
                  showCollectionPicker = true
                #endif
              },
              onDeleteRequested: onDeleteRequested,
              onEditRequested: {
                showEditSheet = true
              },
              onMutationCompleted: onMutationCompleted
            )
            .id(item.seriesId)
          }
        }
      }
    }
    .sheet(isPresented: $showCollectionPicker) {
      CollectionPickerSheet(
        seriesId: series.id,
        onSelect: { collectionId in
          addToCollection(collectionId: collectionId)
        }
      )
    }
    .sheet(isPresented: $showEditSheet) {
      SeriesEditSheet(series: series)
    }
  }

  @ViewBuilder
  private var readingProgressSummary: some View {
    HStack(spacing: 4) {
      Label("\(series.booksCount) books", systemImage: ContentIcon.book)
      Text("•")

      switch series.readStatus {
      case .read:
        Label("All read", systemImage: series.readStatusIcon)
          .foregroundColor(series.readStatusColor)
      case .inProgress:
        Image(systemName: series.readStatusIcon)
          .foregroundColor(series.readStatusColor)
        Text(series.booksUnreadCount > 0 ? "\(series.booksUnreadCount) unread" : series.readStatusDisplayName)
          .foregroundColor(series.readStatusColor)
        Text("•")
        Text(progress, format: .percent.precision(.fractionLength(0)))
      case .unread:
        Label(series.readStatusDisplayName, systemImage: series.readStatusIcon)
          .foregroundColor(series.readStatusColor)
      }
    }
  }

  private func addToCollection(collectionId: String) {
    Task {
      do {
        try await CollectionService.addSeriesToCollection(
          collectionId: collectionId,
          seriesIds: [series.id]
        )
        ErrorManager.shared.notify(
          message: String(localized: "notification.series.addedToCollection"))
        onMutationCompleted?()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
    }
  }

}
