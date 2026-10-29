//
// TrackerSeriesSheet.swift
//

import SwiftUI

struct TrackerSeriesSheet: View {
  let seriesId: String
  let libraryId: String
  let seriesTitle: String
  let onLinksChanged: (() async -> Void)?

  @AppStorage("currentAccount") private var current: Current = .init()
  @Environment(\.dismiss) private var dismiss

  @State private var links: [TrackerLink] = []
  @State private var accounts: [TrackerProvider: TrackerAccount] = [:]
  @State private var preferences: TrackerPreferences?
  @State private var isLoading = false
  @State private var editingLink: TrackerLink?

  init(
    seriesId: String,
    libraryId: String,
    seriesTitle: String,
    onLinksChanged: (() async -> Void)? = nil
  ) {
    self.seriesId = seriesId
    self.libraryId = libraryId
    self.seriesTitle = seriesTitle
    self.onLinksChanged = onLinksChanged
  }

  private var webURL: URL? {
    URL(string: current.serverURL + "/account/trackers")
  }

  private var allowsLibrary: Bool {
    preferences?.libraries.isEmpty != false || preferences?.libraries.contains(libraryId) == true
  }

  var body: some View {
    SheetView(title: String(localized: "Trackers"), size: .large, applyFormStyle: true) {
      Form {
        if isLoading && links.isEmpty {
          Section {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          }
        } else if !allowsLibrary {
          Section {
            ContentUnavailableView {
              Label(String(localized: "Trackers Disabled for This Library"), systemImage: "link")
            } description: {
              Text(String(localized: "Enable this library in your tracker preferences to manage links."))
            }
          }
        } else {
          Section {
            if links.isEmpty {
              Text(String(localized: "No linked trackers"))
                .foregroundStyle(.secondary)
            }
            ForEach(links) { link in
              Button {
                editingLink = link
              } label: {
                HStack(spacing: 12) {
                  TrackerLogo(provider: link.provider)
                    .frame(width: 28, height: 28)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(link.provider.displayName)
                    Text(link.displayTitle)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  Spacer()
                  Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
              }
              .adaptiveButtonStyle(.plain)
            }
          } header: {
            Text(String(localized: "Linked Trackers"))
          }

          Section {
            ForEach(TrackerProvider.allCases, id: \.self) { provider in
              if links.contains(where: { $0.provider == provider }) == false {
                if accounts[provider]?.loggedIn == true {
                  Button {
                    editingLink = TrackerLink(
                      seriesId: seriesId,
                      provider: provider,
                      trackId: "",
                      title: nil,
                      trackMode: .auto,
                      chapterOffset: 0,
                      createdDate: "",
                      lastModifiedDate: ""
                    )
                  } label: {
                    Label(provider.displayName, systemImage: "plus")
                      .contentShape(Rectangle())
                  }
                  .adaptiveButtonStyle(.plain)
                } else if let webURL {
                  Link(destination: webURL) {
                    Label(
                      String.localizedStringWithFormat(
                        String(localized: "Connect %@ on Web"), provider.displayName),
                      systemImage: "safari"
                    )
                    .contentShape(Rectangle())
                  }
                }
              }
            }
          } header: {
            Text(String(localized: "Add Tracker"))
          } footer: {
            Text(
              String(
                localized:
                  "Completing books advances linked tracker entries on the server. Progress never moves backward when a book is marked unread."
              ))
          }
        }
      }
    } controls: {
      Button(String(localized: "Done")) { dismiss() }
    }
    .task {
      await load()
    }
    .sheet(item: $editingLink) { link in
      TrackerLinkEditSheet(
        seriesId: seriesId,
        seriesTitle: seriesTitle,
        link: link
      ) {
        await load()
        await onLinksChanged?()
      }
    }
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      async let linksRequest = TrackerService.getLinks(seriesId: seriesId)
      async let preferencesRequest = TrackerService.getPreferences()
      links = try await linksRequest
      preferences = try await preferencesRequest
      for provider in TrackerProvider.allCases {
        accounts[provider] = try await TrackerService.getAccount(provider: provider)
      }
      TrackerCapabilityStore.shared.refreshCompleted(supported: true)
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }
}
