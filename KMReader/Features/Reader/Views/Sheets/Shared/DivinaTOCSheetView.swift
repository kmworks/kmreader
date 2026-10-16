//
// DivinaTOCSheetView.swift
//
//

import SwiftUI

struct DivinaTOCSheetView: View {
  let entries: [ReaderTOCEntry]
  let currentEntryIDs: Set<UUID>
  let scrollTargetID: UUID?
  let onSelect: (ReaderTOCEntry) -> Void

  var body: some View {
    SheetView(title: String(localized: "Table of Contents"), size: .large, applyFormStyle: true) {
      ScrollViewReader { proxy in
        List {
          ForEach(entries) { entry in
            TOCEntryRow(
              entry: entry,
              currentEntryIds: currentEntryIDs,
              onSelect: onSelect
            )
          }
        }
        .optimizedListStyle()
        .onAppear {
          DispatchQueue.main.async {
            guard let scrollTargetID else { return }
            proxy.scrollTo(scrollTargetID, anchor: .center)
          }
        }
      }
    }
    .presentationDragIndicator(.visible)
  }
}

private struct TOCEntryRow: View {
  let entry: ReaderTOCEntry
  let currentEntryIds: Set<UUID>
  let onSelect: (ReaderTOCEntry) -> Void
  let level: Int

  @State private var isExpanded: Bool = false

  init(
    entry: ReaderTOCEntry, currentEntryIds: Set<UUID>,
    onSelect: @escaping (ReaderTOCEntry) -> Void,
    level: Int = 0
  ) {
    self.entry = entry
    self.currentEntryIds = currentEntryIds
    self.onSelect = onSelect
    self.level = level
  }

  private var isCurrent: Bool {
    currentEntryIds.contains(entry.id)
  }

  var body: some View {
    #if os(tvOS)
      Group {
        Button {
          onSelect(entry)
        } label: {
          TOCEntryLabel(entry: entry, isCurrent: isCurrent, level: level)
        }
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 24, leading: 48 + CGFloat(level * 20), bottom: 24, trailing: 48))
        .id(entry.id)

        if let children = entry.children, !children.isEmpty {
          ForEach(children) { child in
            TOCEntryRow(
              entry: child,
              currentEntryIds: currentEntryIds,
              onSelect: onSelect,
              level: level + 1
            )
          }
        }
      }
    #else
      if let children = entry.children, !children.isEmpty {
        DisclosureGroup(isExpanded: $isExpanded) {
          ForEach(children) { child in
            TOCEntryRow(
              entry: child,
              currentEntryIds: currentEntryIds,
              onSelect: onSelect,
              level: level + 1
            )
          }
        } label: {
          Button {
            onSelect(entry)
          } label: {
            TOCEntryLabel(entry: entry, isCurrent: isCurrent, level: level)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        .id(entry.id)
        .onAppear {
          if shouldExpand(entry: entry, children: children) {
            isExpanded = true
          }
        }
      } else {
        Button {
          onSelect(entry)
        } label: {
          TOCEntryLabel(entry: entry, isCurrent: isCurrent, level: level)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(entry.id)
      }
    #endif
  }

  private func shouldExpand(entry: ReaderTOCEntry, children: [ReaderTOCEntry]) -> Bool {
    return containsAnyEntryId(from: currentEntryIds, in: children)
  }

  private func containsAnyEntryId(from entryIds: Set<UUID>, in entries: [ReaderTOCEntry]) -> Bool {
    for entry in entries {
      if entryIds.contains(entry.id) {
        return true
      }
      if let children = entry.children, containsAnyEntryId(from: entryIds, in: children) {
        return true
      }
    }
    return false
  }
}

private struct TOCEntryLabel: View {
  let entry: ReaderTOCEntry
  let isCurrent: Bool
  let level: Int

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(entry.title)
        .foregroundStyle(isCurrent ? .secondary : .primary)
      Spacer()
      if isCurrent {
        Image(systemName: "bookmark.fill")
      }
      Text(entry.pageNumber)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
