//
// BookBatchMetadataRowEditor.swift
//
//

import SwiftUI

struct BookBatchMetadataRowEditor: View {
  @Binding var row: BookBatchMetadataRow

  var body: some View {
    Section {
      TextField(
        String(localized: "Title"),
        text: textBinding(for: .title, keyPath: \.title)
      )
      .lockToggle(isLocked: lockBinding(for: .title, keyPath: \.titleLock))

      TextField(
        String(localized: "Number"),
        text: textBinding(for: .number, keyPath: \.number)
      )
      .lockToggle(isLocked: lockBinding(for: .number, keyPath: \.numberLock))

      TextField(
        String(localized: "Number Sort"),
        text: textBinding(for: .numberSort, keyPath: \.numberSort)
      )
      #if os(iOS)
        .keyboardType(.decimalPad)
      #endif
      .lockToggle(isLocked: lockBinding(for: .numberSort, keyPath: \.numberSortLock))

      TextField(
        String(localized: "Release Date (YYYY-MM-DD)"),
        text: textBinding(for: .releaseDate, keyPath: \.releaseDateString)
      )
      .lockToggle(isLocked: lockBinding(for: .releaseDate, keyPath: \.releaseDateLock))

      TextField(
        String(localized: "ISBN"),
        text: textBinding(for: .isbn, keyPath: \.isbn)
      )
      .lockToggle(isLocked: lockBinding(for: .isbn, keyPath: \.isbnLock))
    } header: {
      Text(row.book.name)
        .lineLimit(1)
    }
  }

  private func textBinding(
    for field: PerBookMetadataField,
    keyPath: WritableKeyPath<BookMetadataUpdate, String>
  ) -> Binding<String> {
    Binding(
      get: { row.values[keyPath: keyPath] },
      set: { newValue in
        row.values[keyPath: keyPath] = newValue
        row.dirtyFields.insert(field)
        setLocked(true, for: field)
      }
    )
  }

  private func lockBinding(
    for field: PerBookMetadataField,
    keyPath: WritableKeyPath<BookMetadataUpdate, Bool>
  ) -> Binding<Bool> {
    Binding(
      get: { row.values[keyPath: keyPath] },
      set: { newValue in
        row.values[keyPath: keyPath] = newValue
        row.touchedLocks.insert(field)
      }
    )
  }

  private func setLocked(_ locked: Bool, for field: PerBookMetadataField) {
    switch field {
    case .title:
      row.values.titleLock = locked
    case .number:
      row.values.numberLock = locked
    case .numberSort:
      row.values.numberSortLock = locked
    case .releaseDate:
      row.values.releaseDateLock = locked
    case .isbn:
      row.values.isbnLock = locked
    }
  }
}
