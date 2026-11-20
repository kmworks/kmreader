//
// BookBatchEditSheet.swift
//
//

import SwiftUI

struct BookBatchEditSheet: View {
  let bookIds: [String]
  let onCompleted: (Set<String>) -> Void

  @Environment(\.dismiss) private var dismiss
  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var selectedTab = 0
  @State private var rows: [String: BookBatchMetadataRow] = [:]
  @State private var isLoading = false
  @State private var loadError: String?
  @State private var enabledFields: Set<BookBatchSharedField> = []
  @State private var sharedLocks: [BookBatchSharedField: Bool] = [:]
  @State private var summary = ""
  @State private var releaseDate = ""
  @State private var isbn = ""
  @State private var authors: [BatchMetadataPair] = []
  @State private var notableEntities: [BatchMetadataPair] = []
  @State private var tags: [String] = []
  @State private var links: [BatchMetadataPair] = []
  @State private var batchController = BatchOperationController()

  private var hasChanges: Bool {
    !enabledFields.isEmpty
      || rows.values.contains { !$0.dirtyFields.isEmpty || !$0.touchedLocks.isEmpty }
  }

  private var canSave: Bool {
    hasChanges && !batchController.isRunning
  }

  var body: some View {
    SheetView(
      title: String(localized: "batch.books.editTitle \(bookIds.count)"),
      size: .large,
      showsCloseButton: !batchController.isRunning,
      applyFormStyle: true
    ) {
      Form {
        Picker("", selection: $selectedTab) {
          Text(String(localized: "Shared Fields")).tag(0)
          Text(String(localized: "Per Book")).tag(1)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .disabled(batchController.isRunning)

        if selectedTab == 0 {
          sharedFields
        } else {
          perBookFields
        }
      }
      .disabled(batchController.isRunning)
    } controls: {
      Button(action: saveChanges) {
        if batchController.isRunning {
          Label(
            "batch.progress \(batchController.completedCount) \(batchController.totalCount)",
            systemImage: "arrow.triangle.2.circlepath"
          )
        } else {
          Label("Save", systemImage: AppIcon.confirm)
        }
      }
      .disabled(!canSave)
    }
    .task(id: bookIds.joined(separator: ",")) {
      await loadBooks()
    }
  }

  @ViewBuilder
  private var sharedFields: some View {
    Section {
      Text("batch.books.sharedHint \(bookIds.count)")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    BatchMetadataField(
      title: String(localized: "Summary"),
      hint: String(localized: "batch.metadata.emptyClears"),
      isEnabled: enabledBinding(for: .summary),
      isLocked: lockBinding(for: .summary)
    ) {
      TextField("Summary", text: $summary, axis: .vertical)
        .lineLimit(3...8)
    }

    BatchMetadataField(
      title: String(localized: "Release Date"),
      hint: String(localized: "batch.metadata.emptyClears"),
      isEnabled: enabledBinding(for: .releaseDate),
      isLocked: lockBinding(for: .releaseDate)
    ) {
      TextField("Release Date (YYYY-MM-DD)", text: $releaseDate)
    }

    BatchMetadataField(
      title: String(localized: "ISBN"),
      hint: String(localized: "batch.metadata.emptyClears"),
      isEnabled: enabledBinding(for: .isbn),
      isLocked: lockBinding(for: .isbn)
    ) {
      TextField("ISBN", text: $isbn)
    }

    BatchMetadataField(
      title: String(localized: "Authors"),
      hint: String(localized: "batch.metadata.replacesAll"),
      isEnabled: enabledBinding(for: .authors),
      isLocked: lockBinding(for: .authors)
    ) {
      BatchPairListEditor(
        firstPlaceholder: String(localized: "Author Name"),
        secondPlaceholder: String(localized: "Role"),
        addLabel: String(localized: "Add Author"),
        pairs: $authors
      )
    }

    BatchMetadataField(
      title: String(localized: "Notable Entities"),
      hint: String(localized: "batch.metadata.replacesAll"),
      isEnabled: enabledBinding(for: .notableEntities),
      isLocked: lockBinding(for: .notableEntities)
    ) {
      BatchPairListEditor(
        firstPlaceholder: String(localized: "Kind"),
        secondPlaceholder: String(localized: "Name"),
        addLabel: String(localized: "Add Entity"),
        pairs: $notableEntities
      )
    }

    BatchMetadataField(
      title: String(localized: "Tags"),
      hint: String(localized: "batch.metadata.replacesAll"),
      isEnabled: enabledBinding(for: .tags),
      isLocked: lockBinding(for: .tags)
    ) {
      BatchStringListEditor(placeholder: String(localized: "Tag"), values: $tags)
    }

    BatchMetadataField(
      title: String(localized: "Links"),
      hint: String(localized: "batch.metadata.replacesAll"),
      isEnabled: enabledBinding(for: .links),
      isLocked: lockBinding(for: .links)
    ) {
      BatchPairListEditor(
        firstPlaceholder: String(localized: "Label"),
        secondPlaceholder: "https://…",
        addLabel: String(localized: "Add Link"),
        pairs: $links
      )
    }
  }

  @ViewBuilder
  private var perBookFields: some View {
    Section {
      Text("batch.books.perBookHint")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    if isLoading {
      HStack {
        Spacer()
        ProgressView()
        Spacer()
      }
    } else if let loadError, rows.isEmpty {
      ContentUnavailableView {
        Label("batch.books.loadFailed", systemImage: "exclamationmark.triangle")
      } description: {
        Text(loadError)
      } actions: {
        Button("Retry") {
          Task { await loadBooks() }
        }
        .adaptiveButtonStyle(.borderedProminent)
      }
    } else {
      if let loadError {
        Section {
          Text(loadError)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }

      Section {
        Button("batch.books.copySortToNumber", action: copySortToNumber)
        HStack {
          Button("batch.books.decrementAll") {
            shiftAllNumberSort(by: -1)
          }
          Spacer()
          Button("batch.books.incrementAll") {
            shiftAllNumberSort(by: 1)
          }
        }
      }

      ForEach(bookIds, id: \.self) { bookId in
        if let row = rows[bookId] {
          BookBatchMetadataRowEditor(row: rowBinding(for: row))
        }
      }
    }
  }

  private func enabledBinding(for field: BookBatchSharedField) -> Binding<Bool> {
    Binding(
      get: { enabledFields.contains(field) },
      set: { enabled in
        if enabled {
          enabledFields.insert(field)
          if sharedLocks[field] == nil {
            sharedLocks[field] = true
          }
        } else {
          enabledFields.remove(field)
        }
      }
    )
  }

  private func lockBinding(for field: BookBatchSharedField) -> Binding<Bool> {
    Binding(
      get: { sharedLocks[field] ?? true },
      set: { sharedLocks[field] = $0 }
    )
  }

  private func rowBinding(for row: BookBatchMetadataRow) -> Binding<BookBatchMetadataRow> {
    Binding(
      get: { rows[row.book.id] ?? row },
      set: { rows[row.book.id] = $0 }
    )
  }

  private func loadBooks() async {
    guard !isLoading else { return }
    isLoading = true
    loadError = nil
    defer { isLoading = false }

    for bookId in bookIds where rows[bookId] == nil {
      do {
        let book = try await BookService.getBook(id: bookId)
        rows[bookId] = BookBatchMetadataRow(book: book)
      } catch {
        loadError = error.localizedDescription
        if rows.isEmpty {
          return
        }
      }
    }
  }

  private func copySortToNumber() {
    for bookId in bookIds {
      guard var row = rows[bookId] else { continue }
      row.values.number = row.values.numberSort
      row.values.numberLock = true
      row.dirtyFields.insert(.number)
      rows[bookId] = row
    }
  }

  private func shiftAllNumberSort(by delta: Double) {
    for bookId in bookIds {
      guard var row = rows[bookId] else { continue }
      let current = Double(row.values.numberSort) ?? 0
      row.values.numberSort = String(current + delta)
      row.values.numberSortLock = true
      row.dirtyFields.insert(.numberSort)
      rows[bookId] = row
    }
  }

  private func saveChanges() {
    guard canSave, validate() else { return }
    let bodies = makeMetadataBodies()

    Task {
      let outcome = await batchController.run(ids: bookIds.filter { bodies[$0]?.isEmpty == false }) {
        bookId in
        guard let metadata = bodies[bookId] else { return }
        try await BookService.updateBookMetadata(bookId: bookId, metadata: metadata)
      }

      if !outcome.succeeded.isEmpty {
        let seriesIds = Set(outcome.succeeded.compactMap { rows[$0]?.book.seriesId })
        await SyncService.syncVisitedItems(
          bookIds: Set(outcome.succeeded),
          seriesIds: seriesIds
        )
        await ContentProjectionNotifier.postBooksAndSeriesDidChange(
          bookIds: outcome.succeeded,
          instanceId: current.instanceId,
          reason: .content
        )
        await DashboardSectionRefreshNotifier.post(
          sections: DashboardSectionRefreshNotifier.bookContentSections
            .union(DashboardSectionRefreshNotifier.seriesContentSections),
          source: .manual,
          reason: "Book metadata batch updated"
        )
      }

      if let firstError = outcome.firstError {
        ErrorManager.shared.alertBatchFailure(
          failedCount: outcome.failed.count,
          totalCount: outcome.succeeded.count + outcome.failed.count,
          error: firstError
        )
      } else {
        ErrorManager.shared.notify(
          message: String(localized: "batch.books.updated \(outcome.succeeded.count)")
        )
      }

      onCompleted(Set(outcome.failed))
      dismiss()
    }
  }

  private func validate() -> Bool {
    if enabledFields.contains(.releaseDate), !isValidDateOrEmpty(releaseDate) {
      return reportValidationFailure()
    }
    if enabledFields.contains(.isbn), !isValidISBNOrEmpty(isbn) {
      return reportValidationFailure()
    }
    if enabledFields.contains(.links), !links.allSatisfy({ isValidLink($0) }) {
      return reportValidationFailure()
    }

    for row in rows.values {
      if row.dirtyFields.contains(.title),
        row.values.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return reportValidationFailure()
      }
      if row.dirtyFields.contains(.number),
        row.values.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return reportValidationFailure()
      }
      if row.dirtyFields.contains(.numberSort),
        Double(row.values.numberSort)?.isFinite != true
      {
        return reportValidationFailure()
      }
      if row.dirtyFields.contains(.releaseDate), !isValidDateOrEmpty(row.values.releaseDateString) {
        return reportValidationFailure()
      }
      if row.dirtyFields.contains(.isbn), !isValidISBNOrEmpty(row.values.isbn) {
        return reportValidationFailure()
      }
    }
    return true
  }

  private func reportValidationFailure() -> Bool {
    ErrorManager.shared.alert(message: String(localized: "batch.validation.invalid"))
    return false
  }

  private func isValidDateOrEmpty(_ value: String) -> Bool {
    guard !value.isEmpty else { return true }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter.date(from: value) != nil
  }

  private func isValidISBNOrEmpty(_ value: String) -> Bool {
    let digits = value.filter { $0 >= "0" && $0 <= "9" }
    guard !digits.isEmpty else { return true }
    guard digits.count == 13, digits.hasPrefix("978") || digits.hasPrefix("979") else {
      return false
    }
    var numbers: [Int] = []
    for character in digits {
      guard let number = character.wholeNumberValue else { return false }
      numbers.append(number)
    }
    let checksum = numbers.enumerated().reduce(0) { result, item in
      result + item.element * (item.offset.isMultiple(of: 2) ? 1 : 3)
    }
    return checksum.isMultiple(of: 10)
  }

  private func isValidLink(_ pair: BatchMetadataPair) -> Bool {
    guard let url = URL(string: pair.second), let scheme = url.scheme else { return false }
    return !scheme.isEmpty && pair.second.count > scheme.count + 1
  }

  private func makeMetadataBodies() -> [String: [String: Any]] {
    var shared: [String: Any] = [:]

    if enabledFields.contains(.summary) {
      shared["summary"] = nullableString(summary)
      shared["summaryLock"] = sharedLocks[.summary] ?? true
    }
    if enabledFields.contains(.releaseDate) {
      shared["releaseDate"] = nullableString(releaseDate)
      shared["releaseDateLock"] = sharedLocks[.releaseDate] ?? true
    }
    if enabledFields.contains(.isbn) {
      shared["isbn"] = nullableString(isbn)
      shared["isbnLock"] = sharedLocks[.isbn] ?? true
    }
    if enabledFields.contains(.authors) {
      shared["authors"] = authors.map { ["name": $0.first, "role": $0.second] }
      shared["authorsLock"] = sharedLocks[.authors] ?? true
    }
    if enabledFields.contains(.notableEntities) {
      shared["notableEntities"] = notableEntities.map { ["kind": $0.first, "name": $0.second] }
      shared["notableEntitiesLock"] = sharedLocks[.notableEntities] ?? true
    }
    if enabledFields.contains(.tags) {
      shared["tags"] = tags
      shared["tagsLock"] = sharedLocks[.tags] ?? true
    }
    if enabledFields.contains(.links) {
      shared["links"] = links.map { ["label": $0.first, "url": $0.second] }
      shared["linksLock"] = sharedLocks[.links] ?? true
    }

    var bodies: [String: [String: Any]] = [:]
    for bookId in bookIds {
      var body = shared
      if let row = rows[bookId] {
        applyPerBookChanges(row, to: &body)
      }
      bodies[bookId] = body
    }
    return bodies
  }

  private func applyPerBookChanges(
    _ row: BookBatchMetadataRow,
    to body: inout [String: Any]
  ) {
    let fields = row.dirtyFields.union(row.touchedLocks)
    for field in fields {
      switch field {
      case .title:
        if row.dirtyFields.contains(field) {
          body["title"] = row.values.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        body["titleLock"] = row.values.titleLock
      case .number:
        if row.dirtyFields.contains(field) {
          body["number"] = row.values.number.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        body["numberLock"] = row.values.numberLock
      case .numberSort:
        if row.dirtyFields.contains(field) {
          body["numberSort"] = Double(row.values.numberSort) ?? 0
        }
        body["numberSortLock"] = row.values.numberSortLock
      case .releaseDate:
        if row.dirtyFields.contains(field) {
          body["releaseDate"] = nullableString(row.values.releaseDateString)
        }
        body["releaseDateLock"] = row.values.releaseDateLock
      case .isbn:
        if row.dirtyFields.contains(field) {
          body["isbn"] = nullableString(row.values.isbn)
        }
        body["isbnLock"] = row.values.isbnLock
      }
    }
  }

  private func nullableString(_ value: String) -> Any {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? NSNull() : trimmed
  }
}
