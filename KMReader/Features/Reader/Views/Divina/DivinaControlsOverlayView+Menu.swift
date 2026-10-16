//
// DivinaControlsOverlayView+Menu.swift
//
//

import SwiftUI

extension DivinaControlsOverlayView {
  private var enableDualPageOptions: Bool {
    return readingDirection != .webtoon && readingDirection != .vertical && pageLayout.supportsDualPageOptions
  }

  private var pageSoloActions: [ReaderPageSoloActions.Action] {
    ReaderPageSoloActions.resolve(
      supportsDualPageOptions: enableDualPageOptions,
      dualPage: dualPage,
      readingDirection: readingDirection,
      currentPageID: currentPageID,
      currentPairIDs: viewModel.currentViewItem()?.pagePairIDs,
      isCurrentPageWide: viewModel.isCurrentPageWide,
      isCurrentPageSolo: viewModel.isCurrentPageSolo,
      displayPageNumber: displayPageNumber(for:)
    )
  }

  #if os(iOS) || os(macOS)
    private func sharePage(id: ReaderPageID) {
      Task {
        let image =
          await viewModel.originalPageImage(for: id)
          ?? viewModel.preloadedImage(for: id)
        guard let image, let page = viewModel.page(for: id) else { return }
        await ImageShareHelper.share(image: image, fileName: page.fileName)
      }
    }

  #endif

  @ViewBuilder
  func menuContent() -> some View {
    Section {
      Picker(selection: $readingDirection) {
        ForEach(ReadingDirection.availableCases, id: \.self) { direction in
          Label(direction.displayName, systemImage: direction.icon)
            .tag(direction)
        }
      } label: {
        Label(String(localized: "Reading Direction"), systemImage: readingDirection.icon)
      }
      .pickerStyle(.menu)

      if readingDirection != .webtoon && readingDirection != .vertical {
        Picker(selection: $pageLayout) {
          ForEach(PageLayout.allCases, id: \.self) { layout in
            Label(layout.displayName, systemImage: layout.icon)
              .tag(layout)
          }
        } label: {
          Label(String(localized: "Page Layout"), systemImage: pageLayout.icon)
        }
        .pickerStyle(.menu)
      }

      if readingDirection != .webtoon {
        Picker(selection: $splitWidePageMode) {
          ForEach(SplitWidePageMode.allCases, id: \.self) { mode in
            Label(mode.displayName, systemImage: mode.icon).tag(mode)
          }
        } label: {
          Label(String(localized: "Split Wide Pages"), systemImage: splitWidePageMode.icon)
        }
        .pickerStyle(.menu)

        Picker(selection: $rotation) {
          ForEach(ReaderRotation.allCases, id: \.self) { rotation in
            Text(verbatim: rotation.displayName).tag(rotation)
          }
        } label: {
          Label(String(localized: "Page Rotation"), systemImage: "rotate.right")
        }
        .pickerStyle(.menu)
      }
    } header: {
      Text(String(localized: "Current Reading Options"))
    }

    Section {
      Button {
        showingReaderSettingsSheet = true
      } label: {
        Label(String(localized: "Reader Settings"), systemImage: AppIcon.settings)
      }

      #if os(iOS) || os(macOS)
        Button {
          viewModel.setMangaTranslationEnabled(!viewModel.mangaTranslationEnabled)
        } label: {
          Label(
            String(localized: "Manga Translation"),
            systemImage: viewModel.mangaTranslationEnabled
              ? AppIcon.confirm : AppIcon.mangaTranslation
          )
        }
      #endif
    }

    #if os(iOS) || os(macOS)
      if currentPageID != nil {
        Section {
          if dualPage, let pair = viewModel.currentViewItem()?.pagePairIDs {
            sharePageButton(for: pair.first)
            if let second = pair.second {
              sharePageButton(for: second)
            }
          } else if let currentPageID {
            sharePageButton(for: currentPageID)
          }

          ForEach(pageSoloActions) { action in
            Button {
              viewModel.toggleSoloPage(action.pageID)
            } label: {
              Label(action.title, systemImage: action.systemImage)
            }
          }
        } header: {
          Text(String(localized: "Current Page"))
        }
      }
    #endif

    Section {
      pageNavigation()
    } header: {
      Text(String(localized: "Page Navigation"))
    }

    Section {
      bookNavigation()
    } header: {
      Text(String(localized: "Book Navigation"))
    }
  }

  @ViewBuilder
  private func pageNavigation() -> some View {
    if !viewModel.tableOfContents.isEmpty {
      Button {
        showingTOCSheet = true
      } label: {
        Label(String(localized: "Table of Contents"), systemImage: "list.bullet")
      }
    }
    Button {
      guard viewModel.hasPages else { return }
      showingPageJumpSheet = true
    } label: {
      Label(String(localized: "Jump to Page"), systemImage: AppIcon.pageJump)
    }
    .disabled(!viewModel.hasPages)
  }

  @ViewBuilder
  private func bookNavigation() -> some View {
    if let previousBook, let onPreviousBook {
      let previousNumber =
        previousBook.metadata.number.isEmpty
        ? nil
        : previousBook.metadata.number
      Button {
        onPreviousBook(previousBook.id)
      } label: {
        Label(
          "\(String(localized: "reader.previousBook")) #\(previousNumber ?? "-")",
          systemImage: "chevron.left"
        )
      }
    }

    if let nextBook, let onNextBook {
      let nextNumber =
        nextBook.metadata.number.isEmpty
        ? nil
        : nextBook.metadata.number
      Button {
        onNextBook(nextBook.id)
      } label: {
        Label(
          "\(String(localized: "reader.nextBook")) #\(nextNumber ?? "-")",
          systemImage: "chevron.right"
        )
      }
    }
  }

  #if os(iOS) || os(macOS)
    @ViewBuilder
    private func sharePageButton(for pageID: ReaderPageID) -> some View {
      Button {
        sharePage(id: pageID)
      } label: {
        Label(
          String.localizedStringWithFormat(
            String(localized: "Share Page %d"), displayPageNumber(for: pageID)),
          systemImage: AppIcon.share
        )
      }
    }
  #endif
}
