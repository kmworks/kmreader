//
// ReadListBookBrowseOptionsSheet.swift
//
//

import SwiftUI

struct ReadListBookBrowseOptionsSheet: View {
  @Binding var browseOpts: ReadListBookBrowseOptions
  @Environment(\.dismiss) private var dismiss
  @State private var tempOpts: ReadListBookBrowseOptions
  @State private var showSaveFilterSheet = false
  let readListId: String?

  init(browseOpts: Binding<ReadListBookBrowseOptions>, readListId: String? = nil) {
    self._browseOpts = browseOpts
    self._tempOpts = State(initialValue: browseOpts.wrappedValue)
    self.readListId = readListId
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

        Section(String(localized: "Flags")) {
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

        MetadataFilterSection(
          metadataFilter: $tempOpts.metadataFilter,
          readListId: readListId,
          showAuthors: true,
          showTags: true
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
        filterType: .readListBooks,
        readListOptions: tempOpts
      )
    }
  }

  private func resetOptions() {
    withAnimation {
      tempOpts = ReadListBookBrowseOptions()
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
}
