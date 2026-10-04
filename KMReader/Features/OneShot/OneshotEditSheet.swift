//
// OneshotEditSheet.swift
//
//

import SwiftUI

struct OneshotEditSheet: View {
  let series: Series
  let book: Book
  @Environment(\.dismiss) private var dismiss
  @State private var seriesMetadataUpdate: SeriesMetadataUpdate
  @State private var bookMetadataUpdate: BookMetadataUpdate
  @State private var isSaving = false

  @State private var selectedTab = 0

  private var releaseDatePickerBinding: Binding<Date> {
    Binding(
      get: { bookMetadataUpdate.releaseDate ?? Date(timeIntervalSince1970: 0) },
      set: {
        bookMetadataUpdate.releaseDate = $0
        bookMetadataUpdate.releaseDateLock = true
      }
    )
  }

  // Input fields for adding new items
  @State private var newAuthorName: String = ""
  @State private var newAuthorRole: AuthorRole = .writer
  @State private var customRoleName: String = ""
  @State private var newGenre: String = ""
  @State private var newBookTag: String = ""
  @State private var newSharingLabel: String = ""
  @State private var newLinkLabel: String = ""
  @State private var newLinkURL: String = ""

  init(series: Series, book: Book) {
    self.series = series
    self.book = book
    _seriesMetadataUpdate = State(initialValue: SeriesMetadataUpdate.from(series))
    _bookMetadataUpdate = State(initialValue: BookMetadataUpdate.from(book))
  }

  var body: some View {
    SheetView(title: String(localized: "Edit Oneshot"), size: .large, applyFormStyle: true) {
      Form {
        Picker("", selection: $selectedTab) {
          Text(String(localized: "oneshot.edit.tab.general", defaultValue: "General")).tag(0)
          Text(String(localized: "oneshot.edit.tab.authors", defaultValue: "Authors")).tag(1)
          Text(String(localized: "oneshot.edit.tab.tags", defaultValue: "Tags")).tag(2)
          Text(String(localized: "oneshot.edit.tab.links", defaultValue: "Links")).tag(3)
          Text(String(localized: "oneshot.edit.tab.sharing", defaultValue: "Sharing")).tag(4)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        switch selectedTab {
        case 0: generalTab
        case 1: authorsTab
        case 2: tagsTab
        case 3: linksTab
        case 4: sharingTab
        default: EmptyView()
        }
      }
    } controls: {
      Button(action: saveChanges) {
        if isSaving {
          LoadingIcon()
        } else {
          Label("Save", systemImage: "checkmark")
        }
      }
      .disabled(isSaving)
    }
  }

  private var generalTab: some View {
    Group {
      basicInformationSection
      readingSettingsSection
    }
  }

  private var authorsTab: some View {
    authorsSection
  }

  private var tagsTab: some View {
    Group {
      genresSection
      bookTagsSection
    }
  }

  private var linksTab: some View {
    linksSection
  }

  private var sharingTab: some View {
    sharingLabelsSection
  }

  // MARK: - Sections

  private var basicInformationSection: some View {
    Section("Basic Information") {
      TextField("Title", text: $bookMetadataUpdate.title)
        .lockToggle(isLocked: $bookMetadataUpdate.titleLock)
        .onChange(of: bookMetadataUpdate.title) { bookMetadataUpdate.titleLock = true }
      TextField("Sort Title", text: $seriesMetadataUpdate.titleSort)
        .lockToggle(isLocked: $seriesMetadataUpdate.titleSortLock)
        .onChange(of: seriesMetadataUpdate.titleSort) { seriesMetadataUpdate.titleSortLock = true }
      TextField("Summary", text: $bookMetadataUpdate.summary, axis: .vertical)
        .lineLimit(3...10)
        .lockToggle(isLocked: $bookMetadataUpdate.summaryLock, alignment: .top)
        .onChange(of: bookMetadataUpdate.summary) { bookMetadataUpdate.summaryLock = true }

      #if os(tvOS)
        HStack {
          TextField("Release Date (YYYY-MM-DD)", text: $bookMetadataUpdate.releaseDateString)
            .onChange(of: bookMetadataUpdate.releaseDateString) { _, newValue in
              let formatter = ISO8601DateFormatter()
              formatter.formatOptions = [.withFullDate]
              bookMetadataUpdate.releaseDate = formatter.date(from: newValue)
              bookMetadataUpdate.releaseDateLock = true
            }

          if !bookMetadataUpdate.releaseDateString.isEmpty {
            Button(action: {
              withAnimation {
                bookMetadataUpdate.releaseDateString = ""
                bookMetadataUpdate.releaseDate = nil
                bookMetadataUpdate.releaseDateLock = true
              }
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
            .adaptiveButtonStyle(.plain)
          }
        }
        .lockToggle(isLocked: $bookMetadataUpdate.releaseDateLock)
      #else
        HStack {
          DatePicker(
            "Release Date",
            selection: releaseDatePickerBinding,
            displayedComponents: .date
          )
          .datePickerStyle(.compact)

          if bookMetadataUpdate.releaseDate != nil {
            Button(action: {
              withAnimation {
                bookMetadataUpdate.releaseDate = nil
                bookMetadataUpdate.releaseDateLock = true
              }
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
            .adaptiveButtonStyle(.plain)
          }
        }
        .lockToggle(isLocked: $bookMetadataUpdate.releaseDateLock)
      #endif

      TextField("ISBN", text: $bookMetadataUpdate.isbn)
        #if os(iOS) || os(tvOS)
          .keyboardType(.default)
        #endif
        .lockToggle(isLocked: $bookMetadataUpdate.isbnLock)
        .onChange(of: bookMetadataUpdate.isbn) { bookMetadataUpdate.isbnLock = true }
      TextField("Publisher", text: $seriesMetadataUpdate.publisher)
        .lockToggle(isLocked: $seriesMetadataUpdate.publisherLock)
        .onChange(of: seriesMetadataUpdate.publisher) { seriesMetadataUpdate.publisherLock = true }
      TextField("Age Rating", text: $seriesMetadataUpdate.ageRating)
        #if os(iOS) || os(tvOS)
          .keyboardType(.numberPad)
        #endif
        .lockToggle(isLocked: $seriesMetadataUpdate.ageRatingLock)
        .onChange(of: seriesMetadataUpdate.ageRating) { seriesMetadataUpdate.ageRatingLock = true }
    }
  }

  private var readingSettingsSection: some View {
    Section("Reading Settings") {
      Picker("Reading Direction", selection: $seriesMetadataUpdate.readingDirection) {
        ForEach(ReadingDirection.allCases, id: \.self) { direction in
          Text(direction.displayName).tag(direction)
        }
      }
      .lockToggle(isLocked: $seriesMetadataUpdate.readingDirectionLock)
      .onChange(of: seriesMetadataUpdate.readingDirection) { seriesMetadataUpdate.readingDirectionLock = true }

      LanguagePicker(selectedLanguage: $seriesMetadataUpdate.language)
        .lockToggle(isLocked: $seriesMetadataUpdate.languageLock)
        .onChange(of: seriesMetadataUpdate.language) { seriesMetadataUpdate.languageLock = true }
    }
  }

  private var authorsSection: some View {
    Section {
      ForEach(bookMetadataUpdate.authors.indices, id: \.self) { index in
        HStack {
          VStack(alignment: .leading) {
            Text(bookMetadataUpdate.authors[index].name)
            Text(bookMetadataUpdate.authors[index].role.displayName)
              .font(.caption)
              .foregroundColor(.secondary)
          }
          Spacer()
          Button(role: .destructive) {
            let indexToRemove = index
            withAnimation {
              bookMetadataUpdate.authors.remove(at: indexToRemove)
              bookMetadataUpdate.authorsLock = true
            }
          } label: {
            Image(systemName: "trash")
              .padding(8)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(Text("Delete"))
        }
      }
      HStack {
        TextField("Name", text: $newAuthorName)
          .onSubmit { commitPendingAuthor() }
        Picker("Role", selection: $newAuthorRole) {
          ForEach(AuthorRole.predefinedCases, id: \.self) { role in
            Text(role.displayName).tag(role)
          }
          Text("Custom").tag(AuthorRole.custom(""))
        }
        .frame(maxWidth: 150)
      }

      if case .custom = newAuthorRole {
        HStack {
          TextField("Custom Role", text: $customRoleName)
            .onSubmit { commitPendingAuthor() }
        }
      }

      // Own form row: a row shared with the Picker becomes the Picker's tap target.
      Button(action: commitPendingAuthor) {
        Label("Add Author", systemImage: "plus.circle.fill")
          .frame(maxWidth: .infinity)
      }
      .adaptiveButtonStyle(hasPendingAuthor ? .borderedProminent : .borderless)
      .disabled(!hasPendingAuthor)
      .opacity(hasPendingAuthor ? 1 : 0.5)
    } header: {
      Text("Authors")
        .lockToggle(isLocked: $bookMetadataUpdate.authorsLock)
    }
  }

  private var hasPendingAuthor: Bool {
    !newAuthorName.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingAuthor() {
    let name = newAuthorName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    let finalRole: AuthorRole
    if case .custom = newAuthorRole {
      finalRole = .custom(customRoleName.isEmpty ? "Custom" : customRoleName)
    } else {
      finalRole = newAuthorRole
    }
    withAnimation {
      bookMetadataUpdate.authors.append(Author(name: name, role: finalRole))
      bookMetadataUpdate.authorsLock = true
      newAuthorName = ""
      newAuthorRole = .writer
      customRoleName = ""
    }
  }

  private var genresSection: some View {
    Section {
      ForEach(seriesMetadataUpdate.genres.indices, id: \.self) { index in
        HStack {
          Text(seriesMetadataUpdate.genres[index])
          Spacer()
          Button(role: .destructive) {
            let indexToRemove = index
            withAnimation {
              seriesMetadataUpdate.genres.remove(at: indexToRemove)
              seriesMetadataUpdate.genresLock = true
            }
          } label: {
            Image(systemName: "trash")
              .padding(8)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(Text("Delete"))
        }
      }
      HStack {
        TextField("Genre", text: $newGenre)
          .onSubmit { commitPendingGenre() }
        Button(action: commitPendingGenre) {
          Image(systemName: "plus.circle.fill")
        }
        .disabled(!hasPendingGenre)
      }
    } header: {
      Text("Genres")
        .lockToggle(isLocked: $seriesMetadataUpdate.genresLock)
    }
  }

  private var hasPendingGenre: Bool {
    !newGenre.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingGenre() {
    let genre = newGenre.trimmingCharacters(in: .whitespaces)
    guard !genre.isEmpty, !seriesMetadataUpdate.genres.contains(genre) else { return }
    withAnimation {
      seriesMetadataUpdate.genres.append(genre)
      seriesMetadataUpdate.genresLock = true
      newGenre = ""
    }
  }

  private var bookTagsSection: some View {
    Section {
      ForEach(bookMetadataUpdate.tags.indices, id: \.self) { index in
        HStack {
          Text(bookMetadataUpdate.tags[index])
          Spacer()
          Button(role: .destructive) {
            let indexToRemove = index
            withAnimation {
              bookMetadataUpdate.tags.remove(at: indexToRemove)
              bookMetadataUpdate.tagsLock = true
            }
          } label: {
            Image(systemName: "trash")
              .padding(8)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(Text("Delete"))
        }
      }
      HStack {
        TextField("Tag", text: $newBookTag)
          .onSubmit { commitPendingBookTag() }
        Button(action: commitPendingBookTag) {
          Image(systemName: "plus.circle.fill")
        }
        .disabled(!hasPendingBookTag)
      }
    } header: {
      Text("Tags")
        .lockToggle(isLocked: $bookMetadataUpdate.tagsLock)
    }
  }

  private var hasPendingBookTag: Bool {
    !newBookTag.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingBookTag() {
    let tag = newBookTag.trimmingCharacters(in: .whitespaces)
    guard !tag.isEmpty, !bookMetadataUpdate.tags.contains(tag) else { return }
    withAnimation {
      bookMetadataUpdate.tags.append(tag)
      bookMetadataUpdate.tagsLock = true
      newBookTag = ""
    }
  }

  private var sharingLabelsSection: some View {
    Section {
      ForEach(seriesMetadataUpdate.sharingLabels.indices, id: \.self) { index in
        HStack {
          Text(seriesMetadataUpdate.sharingLabels[index])
          Spacer()
          Button(role: .destructive) {
            let indexToRemove = index
            withAnimation {
              seriesMetadataUpdate.sharingLabels.remove(at: indexToRemove)
              seriesMetadataUpdate.sharingLabelsLock = true
            }
          } label: {
            Image(systemName: "trash")
              .padding(8)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(Text("Delete"))
        }
      }
      HStack {
        TextField("Label", text: $newSharingLabel)
          .onSubmit { commitPendingSharingLabel() }
        Button(action: commitPendingSharingLabel) {
          Image(systemName: "plus.circle.fill")
        }
        .disabled(!hasPendingSharingLabel)
      }
    } header: {
      Text("Sharing Labels")
        .lockToggle(isLocked: $seriesMetadataUpdate.sharingLabelsLock)
    }
  }

  private var hasPendingSharingLabel: Bool {
    !newSharingLabel.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingSharingLabel() {
    let label = newSharingLabel.trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty, !seriesMetadataUpdate.sharingLabels.contains(label) else { return }
    withAnimation {
      seriesMetadataUpdate.sharingLabels.append(label)
      seriesMetadataUpdate.sharingLabelsLock = true
      newSharingLabel = ""
    }
  }

  private var linksSection: some View {
    Section {
      ForEach(bookMetadataUpdate.links.indices, id: \.self) { index in
        VStack(alignment: .leading) {
          HStack {
            Text(bookMetadataUpdate.links[index].label)
            Spacer()
            Button(role: .destructive) {
              let indexToRemove = index
              withAnimation {
                bookMetadataUpdate.links.remove(at: indexToRemove)
                bookMetadataUpdate.linksLock = true
              }
            } label: {
              Image(systemName: "trash")
                .padding(8)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Delete"))
          }
          Text(bookMetadataUpdate.links[index].url)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      VStack {
        TextField("Label", text: $newLinkLabel)
          .onSubmit { commitPendingLink() }
        TextField("URL", text: $newLinkURL)
          #if os(iOS) || os(tvOS)
            .keyboardType(.URL)
            .autocapitalization(.none)
          #endif
          .onSubmit { commitPendingLink() }
        Button(action: commitPendingLink) {
          Label("Add Link", systemImage: "plus.circle.fill")
        }
        .adaptiveButtonStyle(hasPendingLink ? .borderedProminent : .borderless)
        .disabled(!hasPendingLink)
        .opacity(hasPendingLink ? 1 : 0.5)
      }
    } header: {
      Text("Links")
        .lockToggle(isLocked: $bookMetadataUpdate.linksLock)
    }
  }

  private var hasPendingLink: Bool {
    !newLinkLabel.trimmingCharacters(in: .whitespaces).isEmpty
      && !newLinkURL.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingLink() {
    let label = newLinkLabel.trimmingCharacters(in: .whitespaces)
    let url = newLinkURL.trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty, !url.isEmpty else { return }
    withAnimation {
      bookMetadataUpdate.links.append(WebLink(label: label, url: url))
      bookMetadataUpdate.linksLock = true
      newLinkLabel = ""
      newLinkURL = ""
    }
  }

  // MARK: - Save

  private func saveChanges() {
    isSaving = true
    Task {
      do {
        // Update book metadata
        try await saveBookMetadata()
        // Update series metadata
        try await saveSeriesMetadata()

        _ = try? await SyncService.syncBookAndSeries(bookId: book.id, seriesId: series.id)
        await ContentProjectionNotifier.postBookAndSeriesDidChange(
          bookId: book.id,
          seriesId: series.id,
          reason: .content
        )
        await DashboardSectionRefreshNotifier.post(
          sections: DashboardSectionRefreshNotifier.bookContentSections
            .union(DashboardSectionRefreshNotifier.seriesContentSections),
          source: .manual,
          reason: "One shot metadata updated"
        )
        ErrorManager.shared.notify(message: String(localized: "notification.book.updated"))
        dismiss()
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isSaving = false
    }
  }

  private func saveBookMetadata() async throws {
    let metadata = bookMetadataUpdate.toAPIDict(against: book)
    if !metadata.isEmpty {
      try await BookService.updateBookMetadata(bookId: book.id, metadata: metadata)
    }
  }

  private func saveSeriesMetadata() async throws {
    let metadata = seriesMetadataUpdate.toAPIDict(against: series)
    if !metadata.isEmpty {
      try await SeriesService.updateSeriesMetadata(
        seriesId: series.id, metadata: metadata)
    }
  }
}
