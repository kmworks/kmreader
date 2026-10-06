//
// SeriesEditSheet.swift
//
//

import SwiftUI

struct SeriesEditSheet: View {
  let series: Series
  @Environment(\.dismiss) private var dismiss
  @State private var metadataUpdate: SeriesMetadataUpdate
  @State private var isSaving = false

  @State private var selectedTab = 0

  @State private var newGenre: String = ""
  @State private var newTag: String = ""
  @State private var newLinkLabel: String = ""
  @State private var newLinkURL: String = ""
  @State private var newAlternateTitleLabel: String = ""
  @State private var newAlternateTitle: String = ""
  @State private var newSharingLabel: String = ""

  init(series: Series) {
    self.series = series
    _metadataUpdate = State(initialValue: SeriesMetadataUpdate.from(series))
  }

  var body: some View {
    SheetView(title: String(localized: "Edit Series"), size: .large, applyFormStyle: true) {
      Form {
        Picker("", selection: $selectedTab) {
          Text(String(localized: "series.edit.tab.general", defaultValue: "General")).tag(0)
          Text(String(localized: "series.edit.tab.title", defaultValue: "Title")).tag(1)
          Text(String(localized: "series.edit.tab.tags", defaultValue: "Tags")).tag(2)
          Text(String(localized: "series.edit.tab.links", defaultValue: "Links")).tag(3)
          Text(String(localized: "series.edit.tab.sharing", defaultValue: "Sharing")).tag(4)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())

        switch selectedTab {
        case 0: generalTab
        case 1: titleTab
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
          Label("Save", systemImage: AppIcon.confirm)
        }
      }
      .disabled(isSaving)
    }
  }

  private var generalTab: some View {
    Group {
      Section("Summary") {
        TextField("Summary", text: $metadataUpdate.summary, axis: .vertical)
          .lineLimit(3...10)
          .lockToggle(isLocked: $metadataUpdate.summaryLock, alignment: .top)
          .onChange(of: metadataUpdate.summary) { metadataUpdate.summaryLock = true }
      }

      Section("Status") {
        Picker("Status", selection: $metadataUpdate.status) {
          ForEach(SeriesStatus.allCases, id: \.self) { status in
            Text(status.displayName).tag(status)
          }
        }
        .lockToggle(isLocked: $metadataUpdate.statusLock)
        .onChange(of: metadataUpdate.status) { metadataUpdate.statusLock = true }
      }

      Section("Reading & Language") {
        Picker("Reading Direction", selection: $metadataUpdate.readingDirection) {
          ForEach(ReadingDirection.allCases, id: \.self) { direction in
            Text(direction.displayName).tag(direction)
          }
        }
        .lockToggle(isLocked: $metadataUpdate.readingDirectionLock)
        .onChange(of: metadataUpdate.readingDirection) { metadataUpdate.readingDirectionLock = true }

        LanguagePicker(selectedLanguage: $metadataUpdate.language)
          .lockToggle(isLocked: $metadataUpdate.languageLock)
          .onChange(of: metadataUpdate.language) { metadataUpdate.languageLock = true }
      }

      Section("Publication") {
        TextField("Publisher", text: $metadataUpdate.publisher)
          .lockToggle(isLocked: $metadataUpdate.publisherLock)
          .onChange(of: metadataUpdate.publisher) { metadataUpdate.publisherLock = true }

        TextField("Age Rating", text: $metadataUpdate.ageRating)
          #if os(iOS) || os(tvOS)
            .keyboardType(.numberPad)
          #endif
          .lockToggle(isLocked: $metadataUpdate.ageRatingLock)
          .onChange(of: metadataUpdate.ageRating) { metadataUpdate.ageRatingLock = true }

        TextField("Total Book Count", text: $metadataUpdate.totalBookCount)
          #if os(iOS) || os(tvOS)
            .keyboardType(.numberPad)
          #endif
          .lockToggle(isLocked: $metadataUpdate.totalBookCountLock)
          .onChange(of: metadataUpdate.totalBookCount) { metadataUpdate.totalBookCountLock = true }
      }
    }
  }

  private var titleTab: some View {
    Group {
      Section("Titles") {
        TextField("Title", text: $metadataUpdate.title)
          .lockToggle(isLocked: $metadataUpdate.titleLock)
          .onChange(of: metadataUpdate.title) { metadataUpdate.titleLock = true }
        TextField("Title Sort", text: $metadataUpdate.titleSort)
          .lockToggle(isLocked: $metadataUpdate.titleSortLock)
          .onChange(of: metadataUpdate.titleSort) { metadataUpdate.titleSortLock = true }
      }

      Section {
        ForEach(metadataUpdate.alternateTitles.indices, id: \.self) { index in
          VStack(alignment: .leading) {
            HStack {
              Text(metadataUpdate.alternateTitles[index].label)
              Spacer()
              Button(role: .destructive) {
                let indexToRemove = index
                withAnimation {
                  metadataUpdate.alternateTitles.remove(at: indexToRemove)
                  metadataUpdate.alternateTitlesLock = true
                }
              } label: {
                Image(systemName: AppIcon.delete)
              }
            }
            Text(metadataUpdate.alternateTitles[index].title)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        VStack {
          TextField("Label", text: $newAlternateTitleLabel)
            .onSubmit { commitPendingAlternateTitle() }
          TextField("Title", text: $newAlternateTitle)
            .onSubmit { commitPendingAlternateTitle() }
          Button(action: commitPendingAlternateTitle) {
            Label("Add Alternate Title", systemImage: AppIcon.addRow)
          }
          .adaptiveButtonStyle(hasPendingAlternateTitle ? .borderedProminent : .borderless)
          .disabled(!hasPendingAlternateTitle)
          .opacity(hasPendingAlternateTitle ? 1 : 0.5)
        }
      } header: {
        Text("Alternate Titles")
          .lockToggle(isLocked: $metadataUpdate.alternateTitlesLock)
      }
    }
  }

  private var hasPendingAlternateTitle: Bool {
    !newAlternateTitleLabel.trimmingCharacters(in: .whitespaces).isEmpty
      && !newAlternateTitle.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingAlternateTitle() {
    let label = newAlternateTitleLabel.trimmingCharacters(in: .whitespaces)
    let title = newAlternateTitle.trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty, !title.isEmpty else { return }
    withAnimation {
      metadataUpdate.alternateTitles.append(AlternateTitle(label: label, title: title))
      metadataUpdate.alternateTitlesLock = true
      newAlternateTitleLabel = ""
      newAlternateTitle = ""
    }
  }

  private var tagsTab: some View {
    Group {
      Section {
        ForEach(metadataUpdate.genres.indices, id: \.self) { index in
          HStack {
            Text(metadataUpdate.genres[index])
            Spacer()
            Button(role: .destructive) {
              let indexToRemove = index
              withAnimation {
                metadataUpdate.genres.remove(at: indexToRemove)
                metadataUpdate.genresLock = true
              }
            } label: {
              Image(systemName: AppIcon.delete)
            }
          }
        }
        HStack {
          TextField("Genre", text: $newGenre)
            .onSubmit { commitPendingGenre() }
          Button(action: commitPendingGenre) {
            Image(systemName: AppIcon.addRow)
          }
          .disabled(!hasPendingGenre)
        }
      } header: {
        Text("Genres")
          .lockToggle(isLocked: $metadataUpdate.genresLock)
      }

      Section {
        ForEach(metadataUpdate.tags.indices, id: \.self) { index in
          HStack {
            Text(metadataUpdate.tags[index])
            Spacer()
            Button(role: .destructive) {
              let indexToRemove = index
              withAnimation {
                metadataUpdate.tags.remove(at: indexToRemove)
                metadataUpdate.tagsLock = true
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
          .lockToggle(isLocked: $metadataUpdate.tagsLock)
      }
    }
  }

  private var hasPendingGenre: Bool {
    !newGenre.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var hasPendingTag: Bool {
    !newTag.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingGenre() {
    let genre = newGenre.trimmingCharacters(in: .whitespaces)
    guard !genre.isEmpty, !metadataUpdate.genres.contains(genre) else { return }
    withAnimation {
      metadataUpdate.genres.append(genre)
      metadataUpdate.genresLock = true
      newGenre = ""
    }
  }

  private func commitPendingTag() {
    let tag = newTag.trimmingCharacters(in: .whitespaces)
    guard !tag.isEmpty, !metadataUpdate.tags.contains(tag) else { return }
    withAnimation {
      metadataUpdate.tags.append(tag)
      metadataUpdate.tagsLock = true
      newTag = ""
    }
  }

  private var linksTab: some View {
    Section {
      ForEach(metadataUpdate.links.indices, id: \.self) { index in
        VStack(alignment: .leading) {
          HStack {
            Text(metadataUpdate.links[index].label)
            Spacer()
            Button(role: .destructive) {
              let indexToRemove = index
              withAnimation {
                metadataUpdate.links.remove(at: indexToRemove)
                metadataUpdate.linksLock = true
              }
            } label: {
              Image(systemName: AppIcon.delete)
            }
          }
          Text(metadataUpdate.links[index].url)
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
        .lockToggle(isLocked: $metadataUpdate.linksLock)
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
      metadataUpdate.links.append(WebLink(label: label, url: url))
      metadataUpdate.linksLock = true
      newLinkLabel = ""
      newLinkURL = ""
    }
  }

  private var sharingTab: some View {
    Section {
      ForEach(metadataUpdate.sharingLabels.indices, id: \.self) { index in
        HStack {
          Text(metadataUpdate.sharingLabels[index])
          Spacer()
          Button(role: .destructive) {
            let indexToRemove = index
            withAnimation {
              metadataUpdate.sharingLabels.remove(at: indexToRemove)
              metadataUpdate.sharingLabelsLock = true
            }
          } label: {
            Image(systemName: AppIcon.delete)
          }
        }
      }
      HStack {
        TextField("Label", text: $newSharingLabel)
          .onSubmit { commitPendingSharingLabel() }
        Button(action: commitPendingSharingLabel) {
          Image(systemName: AppIcon.addRow)
        }
        .disabled(!hasPendingSharingLabel)
      }
    } header: {
      Text("Sharing Labels")
        .lockToggle(isLocked: $metadataUpdate.sharingLabelsLock)
    }
  }

  private var hasPendingSharingLabel: Bool {
    !newSharingLabel.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func commitPendingSharingLabel() {
    let label = newSharingLabel.trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty, !metadataUpdate.sharingLabels.contains(label) else { return }
    withAnimation {
      metadataUpdate.sharingLabels.append(label)
      metadataUpdate.sharingLabelsLock = true
      newSharingLabel = ""
    }
  }

  private func saveChanges() {
    isSaving = true
    Task {
      do {
        let metadata = metadataUpdate.toAPIDict(against: series)

        if !metadata.isEmpty {
          try await SeriesService.updateSeriesMetadata(
            seriesId: series.id, metadata: metadata)
          _ = try? await SyncService.syncSeriesDetail(seriesId: series.id)
          await ContentProjectionNotifier.postSeriesDidChange(
            seriesId: series.id, reason: .content)
          await DashboardSectionRefreshNotifier.postSeriesContentChanged(
            source: .manual,
            reason: "Series metadata updated"
          )
          ErrorManager.shared.notify(message: String(localized: "notification.series.updated"))
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
