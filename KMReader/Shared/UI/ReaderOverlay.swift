//
// ReaderOverlay.swift
//
//

import SwiftUI

#if os(iOS) || os(tvOS)
  /// Reader overlay that handles presentation with fullScreenCover
  struct ReaderOverlay: View {
    let namespace: Namespace.ID
    let readerPresentation: ReaderPresentationManager

    private var isReaderPresented: Binding<Bool> {
      Binding(
        get: { readerPresentation.currentSession != nil },
        set: { if !$0 { readerPresentation.closeReader() } }
      )
    }

    var body: some View {
      Color.clear
        .frame(width: 0, height: 0)
        .fullScreenCover(isPresented: isReaderPresented) {
          ReaderContentView(readerPresentation: readerPresentation)
            .navigationTransitionZoomIfAvailable(
              sourceID: readerPresentation.sourceBookId,
              in: namespace
            )
        }
    }
  }

  private struct ReaderContentView: View {
    let readerPresentation: ReaderPresentationManager

    var body: some View {
      Group {
        if let session = readerPresentation.currentSession {
          BookReaderView(
            sessionID: session.id,
            book: session.book,
            incognito: session.incognito,
            readListContext: session.readListContext,
            readerPresentation: readerPresentation,
            onClose: { readerPresentation.closeReader() }
          )
          .id(session.id)
        } else {
          ReaderPlaceholderView {
            readerPresentation.closeReader()
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .komgaHandoff(
        title: readerPresentation.handoffTitle,
        url: readerPresentation.handoffURL,
        scope: .reader
      )
    }
  }

  struct ReaderPlaceholderView: View {
    let onClose: () -> Void

    var body: some View {
      VStack(spacing: 16) {
        ProgressView()
          .progressViewStyle(.circular)

        Text(String(localized: "reader.preparing"))
          .font(.headline)
          .foregroundColor(.secondary)

        Button {
          onClose()
        } label: {
          Label(String(localized: "Cancel"), systemImage: "xmark.circle")
            .font(.headline)
        }
        .adaptiveButtonStyle(.bordered)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(PlatformHelper.systemBackgroundColor.readerIgnoresSafeArea())
    }
  }

#elseif os(macOS)
  struct MacReaderWindowConfigurator: View {
    let readerPresentation: ReaderPresentationManager
    let openWindow: () -> Void

    var body: some View {
      Color.clear
        .onAppear {
          readerPresentation.configureWindowOpener(openWindow)
        }
    }
  }
#endif
