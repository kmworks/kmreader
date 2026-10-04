//
// AccountActivityView.swift
//
//

import SwiftUI

struct AccountActivityView: View {
  @State private var pagination = PaginationState<AuthenticationActivity>(pageSize: 20)
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var lastTriggeredIndex: Int = -1

  var body: some View {
    List {
      if isLoading && pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if pagination.isEmpty {
        Section {
          HStack {
            Spacer()
            VStack(spacing: 8) {
              Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
              Text("No activity found")
                .foregroundColor(.secondary)
            }
            Spacer()
          }
          .padding(.vertical)
          .tvFocusableHighlight()
        }
      } else {
        Section {
          ForEach(Array(pagination.items.enumerated()), id: \.element.id) { index, activity in
            activityRow(activity: activity, index: index)
          }

          if isLoadingMore {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
            .padding(.vertical)
          }
        }
      }
    }
    // Cannot use Form for this, it would cause endless fetch on macOS.
    .optimizedListStyle()
    .platformNavigationTitle(ServerSection.authenticationActivity.title)
    .task {
      await loadActivities(refresh: true)
    }
    .refreshable {
      await loadActivities(refresh: true)
    }
  }

  @ViewBuilder
  private func activityRow(activity: AuthenticationActivity, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: activity.success ? "checkmark.circle.fill" : "xmark.circle.fill")
          .foregroundColor(activity.success ? .green : .red)
        if let source = activity.source {
          Text(source)
            .font(.headline)
        } else {
          Text(activity.success ? "Success" : "Failed")
            .font(.headline)
        }
        Spacer()
        Text(activity.dateTime.formattedMediumDateTime)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if let apiKeyComment = activity.apiKeyComment {
        HStack {
          detailRowIcon("key")
          Text(apiKeyComment)
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }

      if let userAgent = activity.userAgent {
        HStack {
          detailRowIcon("desktopcomputer")
          Text(userAgent).lineLimit(1)
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }

      if let ip = activity.ip {
        HStack {
          detailRowIcon("network")
          Text(ip)
        }
        .font(.caption)
        .foregroundColor(.secondary)
      }

      if let error = activity.error {
        HStack {
          detailRowIcon("exclamationmark.triangle.fill")
          Text(error)
        }
        .font(.caption)
        .foregroundColor(.red)
      }
    }
    .tvFocusableHighlight()
    #if os(tvOS)
      .padding(.vertical, 12)
      .padding(.horizontal, 16)
    #else
      .padding(.vertical, 4)
    #endif
    .onAppear {
      guard index >= pagination.items.count - 3,
        pagination.hasMorePages,
        !isLoadingMore,
        lastTriggeredIndex != index
      else {
        return
      }
      lastTriggeredIndex = index
      Task {
        await loadMoreActivities()
      }
    }
  }

  private func detailRowIcon(_ name: String) -> some View {
    // Fixed width so detail-row texts start at the same x offset despite
    // SF Symbols having different natural widths.
    Image(systemName: name)
      .frame(width: 16)
  }

  private func loadActivities(refresh: Bool = false) async {
    if refresh {
      withAnimation {
        pagination.reset()
      }
      lastTriggeredIndex = -1
    }

    withAnimation {
      isLoading = true
    }

    do {
      let page = try await AuthService.getAuthenticationActivity(
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredIndex = -1
    } catch {
      ErrorManager.shared.alert(error: error)
    }

    withAnimation {
      isLoading = false
    }
  }

  private func loadMoreActivities() async {
    guard pagination.hasMorePages && !isLoadingMore else { return }

    withAnimation {
      isLoadingMore = true
    }

    do {
      let page = try await AuthService.getAuthenticationActivity(
        page: pagination.currentPage,
        size: pagination.pageSize
      )
      withAnimation {
        _ = pagination.applyPage(page.content)
        pagination.advance(moreAvailable: !page.last)
      }
      lastTriggeredIndex = -1
    } catch {
      ErrorManager.shared.alert(error: error)
    }

    withAnimation {
      isLoadingMore = false
    }
  }
}
