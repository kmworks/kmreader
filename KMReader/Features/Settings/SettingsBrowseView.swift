//
// SettingsBrowseView.swift
//
//

import Foundation
import SwiftUI

struct SettingsBrowseView: View {
  @AppStorage("coverOnlyCards") private var coverOnlyCards: Bool = false
  @AppStorage("cardTextOverlayMode") private var cardTextOverlayMode: Bool = false
  @AppStorage("showBookCardSeriesTitle") private var showBookCardSeriesTitle: Bool = true
  @AppStorage("thumbnailPreserveAspectRatio") private var thumbnailPreserveAspectRatio: Bool = true
  @AppStorage("thumbnailShowShadow") private var thumbnailShowShadow: Bool = true
  @AppStorage("thumbnailShowUnreadIndicator") private var thumbnailShowUnreadIndicator: Bool = true
  @AppStorage("thumbnailShowProgressBar") private var thumbnailShowProgressBar: Bool = true
  @AppStorage("thumbnailBlurUnreadCovers") private var thumbnailBlurUnreadCovers: Bool = false
  @AppStorage("searchIgnoreFilters") private var searchIgnoreFilters: Bool = false

  var body: some View {
    Form {
      Section(header: Text(String(localized: "settings.appearance.search"))) {
        Toggle(isOn: $searchIgnoreFilters) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.searchIgnoreFilters.title"))
            Text(String(localized: "settings.appearance.searchIgnoreFilters.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Section(header: Text(String(localized: "settings.appearance.cards"))) {
        HStack(spacing: 12) {
          SettingsBrowseCardPreview(
            title: "Series Title",
            detail: "12 books",
            unreadCount: 12,
            shouldBlurCover: true
          )
          .frame(maxWidth: .infinity)

          SettingsBrowseCardPreview(
            title: "#12 - Book Title",
            subtitle: "Series Title",
            detail: "200 pages",
            progress: 0.45
          )
          .frame(maxWidth: .infinity)

          SettingsBrowseCardPreview(
            title: "#1 - Book Title",
            subtitle: "Series Title",
            detail: "200 pages",
            showCompletedBadge: true
          )
          .frame(maxWidth: .infinity)
        }

        Toggle(isOn: $cardTextOverlayMode) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.cardTextOverlay.title"))
            Text(String(localized: "settings.appearance.cardTextOverlay.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        if !cardTextOverlayMode {
          Toggle(isOn: $coverOnlyCards) {
            VStack(alignment: .leading, spacing: 4) {
              Text(String(localized: "settings.appearance.coverOnlyCards.title"))
              Text(String(localized: "settings.appearance.coverOnlyCards.caption"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        Toggle(isOn: $showBookCardSeriesTitle) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.showBookCardSeriesTitles.title"))
            Text(String(localized: "settings.appearance.showBookCardSeriesTitles.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        if !cardTextOverlayMode {
          Toggle(isOn: $thumbnailPreserveAspectRatio) {
            VStack(alignment: .leading, spacing: 4) {
              Text(
                String(localized: "settings.appearance.preserveCoverAspectRatio.title"))
              Text(
                String(localized: "settings.appearance.preserveCoverAspectRatio.caption")
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }
        }

        Toggle(isOn: $thumbnailShowShadow) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.coverShowShadow.title"))
            Text(String(localized: "settings.appearance.coverShowShadow.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Toggle(isOn: $thumbnailShowUnreadIndicator) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.coverShowUnreadIndicator.title"))
            Text(String(localized: "settings.appearance.coverShowUnreadIndicator.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Toggle(isOn: $thumbnailBlurUnreadCovers) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.coverBlurUnread.title"))
            Text(String(localized: "settings.appearance.coverBlurUnread.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Toggle(isOn: $thumbnailShowProgressBar) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.appearance.coverShowProgressBar.title"))
            Text(String(localized: "settings.appearance.coverShowProgressBar.caption"))
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "settings.browse.title"))
    .animation(.easeInOut(duration: 0.2), value: cardTextOverlayMode)
  }
}
