//
// BookEditSheet.swift
//
//

import SwiftUI

struct BookEditSheet: View {
  let book: Book
  @Environment(\.dismiss) private var dismiss
  @State private var bookMetadataUpdate: BookMetadataUpdate
  @State private var isSaving = false

  @State private var selectedTab = 0

  @State private var newAuthorName: String = ""
  @State private var newAuthorRole: AuthorRole = .writer
  @State private var showCustomRoleInput: Bool = false
  @State private var customRoleName: String = ""
  @State private var newTag: String = ""
  @State private var newLinkLabel: String = ""
  @State private var newLinkURL: String = ""

  init(book: Book) {
    self.book = book
    _bookMetadataUpdate = State(initialValue: BookMetadataUpdate.from(book))
  }

  var body: some View {
    SheetView(title: String(localized: "Edit Book"), size: .large, applyFormStyle: true) {
      Form {
        Picker("", selection: $selectedTab) {
          Text(String(localized: "book.edit.tab.general", defaultValue: "General")).tag(0)
          Text(String(localized: "book.edit.tab.authors", defaultValue: "Authors")).tag(1)
          Text(String(localized: "book.edit.tab.tags", defaultValue: "Tags")).tag(2)
          Text(String(localized: "book.edit.tab.links", defaultValue: "Links")).tag(3)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        switch selectedTab {
        case 0: generalTab
        case 1: authorsTab
        case 2: tagsTab
        case 3: linksTab
        default: EmptyView()
        }
      }
    } controls: {
      Button(action: saveChanges) {
        if isSaving {
          LoadingIcon()
        } else {
          Label("Save", systemImage: AppIcon.confirm)
        }
      }
      .disabled(isSaving)
    }
  }

  private var generalTab: some View {
    Group {
      Section("Basic Information") {
        TextField("Title", text: $bookMetadataUpdate.title)
          .lockToggle(isLocked: $bookMetadataUpdate.titleLock)
          .onChange(of: bookMetadataUpdate.title) { bookMetadataUpdate.titleLock = true }

        HStack {
          TextField("Number", text: $bookMetadataUpdate.number)
            .lockToggle(isLocked: $bookMetadataUpdate.numberLock)
            .onChange(of: bookMetadataUpdate.number) { bookMetadataUpdate.numberLock = true }
          TextField("Number Sort", text: $bookMetadataUpdate.numberSort)
            #if os(iOS) || os(tvOS)
              .keyboardType(.decimalPad)
            #endif
            .lockToggle(isLocked: $bookMetadataUpdate.numberSortLock)
            .onChange(of: bookMetadataUpdate.numberSort) { bookMetadataUpdate.numberSortLock = true }
        }

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
              selection: Binding(
                get: { bookMetadataUpdate.releaseDate ?? Date(timeIntervalSince1970: 0) },
                set: {
                  bookMetadataUpdate.releaseDate = $0
                  bookMetadataUpdate.releaseDateLock = true
                }
              ),
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
      }

      Section("Summary") {
        TextField("Summary", text: $bookMetadataUpdate.summary, axis: .vertical)
          .lineLimit(3...10)
          .lockToggle(isLocked: $bookMetadataUpdate.summaryLock, alignment: .top)
          .onChange(of: bookMetadataUpdate.summary) { bookMetadataUpdate.summaryLock = true }
      }
    }
  }

  private var authorsTab: some View {
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
            Image(systemName: AppIcon.delete)
          }
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
        Label("Add Author", systemImage: AppIcon.addRow)
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

  private var tagsTab: some View {
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
            Image(systemName: AppIcon.delete)
          }
        }
      }
      HStack {
        TextField("Tag", text: $newTag)
          .onSubmit { commitPendingTag() }
        Button(action: commitPendingTag) {
          Image(systemName: AppIcon.addRow)
        }
        .disabled(!hasPendingTag)
      }
    } header: {
      Text("Tags")
        .lockToggle(isLocked: $bookMetadataUpdate.tagsLock)
    }
  }

  private var hasPendingTag: Bool {
    !newTag.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingTag() {
    let tag = newTag.trimmingCharacters(in: .whitespaces)
    guard !tag.isEmpty, !bookMetadataUpdate.tags.contains(tag) else { return }
    withAnimation {
      bookMetadataUpdate.tags.append(tag)
      bookMetadataUpdate.tagsLock = true
      newTag = ""
    }
  }

  private var linksTab: some View {
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
              Image(systemName: AppIcon.delete)
            }
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
          Label("Add Link", systemImage: AppIcon.addRow)
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

  private func saveChanges() {
    isSaving = true
    Task {
      do {
        let metadata = bookMetadataUpdate.toAPIDict(against: book)

        if !metadata.isEmpty {
          try await BookService.updateBookMetadata(bookId: book.id, metadata: metadata)
          _ = try? await SyncService.syncBookAndSeries(bookId: book.id, seriesId: book.seriesId)
          await ContentProjectionNotifier.postBookAndSeriesDidChange(
            bookId: book.id,
            seriesId: book.seriesId,
            reason: .content
          )
          await DashboardSectionRefreshNotifier.post(
            sections: DashboardSectionRefreshNotifier.bookContentSections
              .union(DashboardSectionRefreshNotifier.seriesContentSections),
            source: .manual,
            reason: "Book metadata updated"
          )
          ErrorManager.shared.notify(message: String(localized: "notification.book.updated"))
          dismiss()
        } else {
          dismiss()
        }
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isSaving = false
    }
  }
}
