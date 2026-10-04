//
// KeyboardHelpOverlay.swift
//
//

import SwiftUI

struct KeyboardHelpOverlay: View {
  let readingDirection: ReadingDirection
  let hasTOC: Bool
  let supportsFullscreenToggle: Bool
  let supportsLiveText: Bool
  let supportsJumpToPage: Bool
  let supportsSearch: Bool
  let supportsToggleControls: Bool
  let hasNextBook: Bool
  let isInteractive: Bool
  let onDismiss: () -> Void

  init(
    readingDirection: ReadingDirection,
    hasTOC: Bool,
    supportsFullscreenToggle: Bool,
    supportsLiveText: Bool,
    supportsJumpToPage: Bool,
    supportsSearch: Bool = false,
    supportsToggleControls: Bool,
    hasNextBook: Bool,
    isInteractive: Bool = true,
    onDismiss: @escaping () -> Void
  ) {
    self.readingDirection = readingDirection
    self.hasTOC = hasTOC
    self.supportsFullscreenToggle = supportsFullscreenToggle
    self.supportsLiveText = supportsLiveText
    self.supportsJumpToPage = supportsJumpToPage
    self.supportsSearch = supportsSearch
    self.supportsToggleControls = supportsToggleControls
    self.hasNextBook = hasNextBook
    self.isInteractive = isInteractive
    self.onDismiss = onDismiss
  }

  var body: some View {
    ZStack {
      if isInteractive {
        Button {
          onDismiss()
        } label: {
          Color.black.opacity(0.5)
        }
        .adaptiveButtonStyle(.plain)
      } else {
        Color.black.opacity(0.5)
      }

      VStack(spacing: 20) {
        Text("Keyboard Shortcuts")
          .font(.title2)
          .fontWeight(.bold)
          .foregroundColor(.white)

        Grid(alignment: .leading, verticalSpacing: 12) {
          HelpRow(key: "ESC", description: "Close reader")
          HelpRow(key: "? / H", description: "Show this help")

          Divider()
            .background(Color.white.opacity(0.3))

          if supportsFullscreenToggle {
            HelpRow(key: "Return", description: "Toggle fullscreen")
          }
          if supportsToggleControls {
            HelpRow(key: "C / Space", description: "Toggle controls")
          }
          if supportsLiveText {
            HelpRow(key: "L", description: "Toggle Live Text")
          }
          if hasTOC {
            HelpRow(key: "T", description: "Table of Contents")
          }
          if supportsJumpToPage {
            HelpRow(key: "J", description: "Jump to page")
          }
          if supportsSearch {
            HelpRow(key: "F", description: "Search")
          }
          if hasNextBook {
            HelpRow(key: "N", description: "Next book")
          }

          Divider()
            .background(Color.white.opacity(0.3))

          // Navigation keys based on reading direction
          Group {
            switch readingDirection {
            case .ltr:
              HelpRow(key: "→", description: "Next page")
              HelpRow(key: "←", description: "Previous page")
            case .rtl:
              HelpRow(key: "←", description: "Next page")
              HelpRow(key: "→", description: "Previous page")
            case .vertical:
              HelpRow(key: "↓", description: "Next page")
              HelpRow(key: "↑", description: "Previous page")
            case .webtoon:
              HelpRow(key: "↓", description: "Scroll down")
              HelpRow(key: "↑", description: "Scroll up")
            }
          }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )

        if isInteractive {
          Button {
            onDismiss()
          } label: {
            Text("Close")
              .foregroundColor(.white)
              .padding(.horizontal, 24)
              .padding(.vertical, 8)
              .background(Color.white.opacity(0.25))
              .cornerRadius(8)
          }
          .adaptiveButtonStyle(.plain)
        }
      }
      .padding(40)
      .frame(maxWidth: 500)
    }
    .readerIgnoresSafeArea()
  }
}

private struct HelpRow: View {
  let key: String
  let description: String

  var body: some View {
    GridRow {
      Text(key)
        .font(.system(.body, design: .monospaced))
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.2))
        .cornerRadius(6)
        // The Grid column tracks the widest key, so larger dynamic type sizes
        // widen the column instead of overflowing it; 130 keeps the default
        // layout unchanged.
        .frame(minWidth: 130, alignment: .leading)

      Text(description)
        .foregroundColor(.white.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
