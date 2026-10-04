//
// CollectionSeriesBrowseOptionsSheet.swift
//
//

import SwiftUI

struct CollectionSeriesBrowseOptionsSheet: View {
  @Binding var browseOpts: CollectionSeriesBrowseOptions
  @Environment(\.dismiss) private var dismiss
  @State private var tempOpts: CollectionSeriesBrowseOptions
  @State private var showSaveFilterSheet = false
  let collectionId: String?

  init(browseOpts: Binding<CollectionSeriesBrowseOptions>, collectionId: String? = nil) {
    self._browseOpts = browseOpts
    self._tempOpts = State(initialValue: browseOpts.wrappedValue)
    self.collectionId = collectionId
  }

  var body: some View {
    SheetView(
      title: String(localized: "Filter"), size: .both, onReset: resetOptions, applyFormStyle: true
    ) {
      Form {
        Section(String(localized: "Read Status")) {
          ForEach(ReadStatus.allCases, id: \.self) { filter in
            Button {
              toggleReadStatus(filter)
            } label: {
              HStack {
                Text(filter.displayName)
                Spacer()
                let state = resolveReadStatusState(
                  for: filter,
                  include: tempOpts.includeReadStatuses,
                  exclude: tempOpts.excludeReadStatuses
                )
                Image(systemName: icon(for: state))
                  .foregroundStyle(color(for: state))
                  .animation(.appCurve(), value: state)
              }
            }
          }
        }

        Section(String(localized: "Series Status")) {
          Picker(String(localized: "Logic"), selection: $tempOpts.seriesStatusLogic) {
            Text(String(localized: "All")).tag(FilterLogic.all)
            Text(String(localized: "Any")).tag(FilterLogic.any)
          }
          .pickerStyle(.segmented)

          ForEach(SeriesStatus.allCases, id: \.self) { filter in
            Button {
              cycleSeriesStatus(filter)
            } label: {
              HStack {
                Text(filter.displayName)
                Spacer()
                let state = state(for: filter)
                Image(systemName: icon(for: state))
                  .foregroundStyle(color(for: state))
                  .animation(.appCurve(), value: state)
              }
            }
          }
        }

        Section(String(localized: "Flags")) {
          Button {
            tempOpts.completeFilter.cycle(to: .yes)
          } label: {
            HStack {
              Text(FilterStrings.complete)
              Spacer()
              let state = tempOpts.completeFilter.state(for: .yes)
              Image(systemName: icon(for: state))
                .foregroundStyle(color(for: state))
                .animation(.appCurve(), value: state)
            }
          }

          Button {
            tempOpts.oneshotFilter.cycle(to: .yes)
          } label: {
            HStack {
              Text(FilterStrings.oneshot)
              Spacer()
              let state = tempOpts.oneshotFilter.state(for: .yes)
              Image(systemName: icon(for: state))
                .foregroundStyle(color(for: state))
                .animation(.appCurve(), value: state)
            }
          }

          Button {
            tempOpts.deletedFilter.cycle(to: .yes)
          } label: {
            HStack {
              Text(FilterStrings.deleted)
              Spacer()
              let state = tempOpts.deletedFilter.state(for: .yes)
              Image(systemName: icon(for: state))
                .foregroundStyle(color(for: state))
                .animation(.appCurve(), value: state)
            }
          }
        }

        // Note: collectionId would need to be passed from parent view
        MetadataFilterSection(
          metadataFilter: $tempOpts.metadataFilter,
          collectionId: collectionId,
          showPublisher: true,
          showAuthors: true,
          showGenres: true,
          showTags: true,
          showLanguages: true,
          showAgeRatings: true,
          showReleaseYears: true
        )

      }
    } controls: {
      Button {
        withAnimation {
          showSaveFilterSheet = true
        }
      } label: {
        Label(String(localized: "Save Filter"), systemImage: "bookmark")
      }
      Button(action: applyChanges) {
        Label(String(localized: "Done"), systemImage: "checkmark")
      }
    }
    .sheet(isPresented: $showSaveFilterSheet) {
      SaveFilterSheet(
        filterType: .collectionSeries,
        collectionOptions: tempOpts
      )
    }
  }

  private func resetOptions() {
    withAnimation {
      tempOpts = CollectionSeriesBrowseOptions()
    }
  }

  private func applyChanges() {
    if tempOpts != browseOpts {
      browseOpts = tempOpts
    }
    dismiss()
  }

  private func icon(for state: TriStateSelection) -> String {
    switch state {
    case .off:
      return "circle"
    case .include:
      return "checkmark.circle.fill"
    case .exclude:
      return "xmark.circle.fill"
    }
  }

  private func color(for state: TriStateSelection) -> Color {
    switch state {
    case .off:
      return .secondary
    case .include:
      return .primary
    case .exclude:
      return .red
    }
  }

  private func state(for status: ReadStatus) -> TriStateSelection {
    if tempOpts.includeReadStatuses.contains(status) {
      return .include
    }
    if tempOpts.excludeReadStatuses.contains(status) {
      return .exclude
    }
    return .off
  }

  private func toggleReadStatus(_ status: ReadStatus) {
    var include = tempOpts.includeReadStatuses
    var exclude = tempOpts.excludeReadStatuses
    KMReader.applyReadStatusToggle(status, include: &include, exclude: &exclude)
    tempOpts.includeReadStatuses = include
    tempOpts.excludeReadStatuses = exclude
  }

  private func state(for status: SeriesStatus) -> TriStateSelection {
    if tempOpts.includeSeriesStatuses.contains(status) {
      return .include
    }
    if tempOpts.excludeSeriesStatuses.contains(status) {
      return .exclude
    }
    return .off
  }

  private func cycleSeriesStatus(_ status: SeriesStatus) {
    if tempOpts.includeSeriesStatuses.contains(status) {
      tempOpts.includeSeriesStatuses.remove(status)
      tempOpts.excludeSeriesStatuses.insert(status)
    } else if tempOpts.excludeSeriesStatuses.contains(status) {
      tempOpts.excludeSeriesStatuses.remove(status)
    } else {
      tempOpts.includeSeriesStatuses.insert(status)
    }
  }
}
