//
// BookReaderView.swift
//
//

import SwiftUI

struct BookReaderView: View {
  let sessionID: UUID
  let book: Book
  let incognito: Bool
  let readListContext: ReaderReadListContext?
  let readerPresentation: ReaderPresentationManager
  let onClose: (() -> Void)?

  @Environment(\.dismiss) private var dismiss

  @AppStorage("useNativePdfReader") private var useNativePdfReader: Bool = true

  private var mediaProfile: MediaProfile {
    book.media.mediaProfileValue ?? .unknown
  }

  private var mediaStatus: MediaStatus {
    book.media.statusValue
  }

  private var closeReader: () -> Void {
    onClose ?? { dismiss() }
  }

  var body: some View {
    Group {
      if book.deleted {
        ReaderUnavailableView(
          icon: "trash.circle",
          title: "Book has been deleted",
          onClose: closeReader
        )
      } else {
        switch mediaStatus {
        case .ready:
          switch mediaProfile {
          case .divina, .unknown:
            DivinaReaderView(
              sessionID: sessionID,
              book: book,
              incognito: incognito,
              readListContext: readListContext,
              readerPresentation: readerPresentation,
              onClose: closeReader
            )
          case .epub:
            if book.media.epubDivinaCompatible ?? false {
              DivinaReaderView(
                sessionID: sessionID,
                book: book,
                incognito: incognito,
                readListContext: readListContext,
                readerPresentation: readerPresentation,
                onClose: closeReader
              )
            } else {
              #if os(iOS) || os(macOS)
                EpubReaderView(
                  sessionID: sessionID,
                  book: book,
                  incognito: incognito,
                  readListContext: readListContext,
                  readerPresentation: readerPresentation,
                  onClose: closeReader
                )
              #else
                ReaderUnavailableView(
                  icon: AppIcon.loadError,
                  title: "EPUB Reader Not Available",
                  message: String(
                    localized:
                      "EPUB reading is only supported on iOS and macOS."
                  ),
                  onClose: closeReader
                )
              #endif
            }
          case .pdf:
            if useNativePdfReader {
              #if os(iOS) || os(macOS)
                PdfReaderView(
                  sessionID: sessionID,
                  book: book,
                  incognito: incognito,
                  readerPresentation: readerPresentation,
                  onClose: closeReader
                )
              #else
                ReaderUnavailableView(
                  icon: "doc.richtext",
                  title: "PDF Reader Not Available",
                  message: String(
                    localized:
                      "PDF reading is only supported on iOS and macOS."
                  ),
                  onClose: closeReader
                )
              #endif
            } else {
              DivinaReaderView(
                sessionID: sessionID,
                book: book,
                incognito: incognito,
                readListContext: readListContext,
                readerPresentation: readerPresentation,
                onClose: closeReader
              )
            }
          }
        default:
          ReaderUnavailableView(
            icon: mediaStatus.icon,
            title: LocalizedStringKey(mediaStatus.message),
            message: book.media.localizedComment,
            onClose: closeReader
          )
        }
      }
    }
    .environment(\.readerActions, .live(readerPresentation: readerPresentation))
    .keepScreenAwakeWhileReading()
  }
}
