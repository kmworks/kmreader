//
// ReadingActionButton.swift
//
//

import SwiftUI

/// Prominent capsule reading action for detail pages: a two-line label (action
/// over a detail line) filling the action card, with an optional resolving
/// spinner.
struct ReadingActionButton: View {
  let label: String
  let detail: Text
  var isResolving: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "book.fill")
          .font(.callout)

        VStack(alignment: .leading, spacing: 1) {
          Text(label)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .contentTransition(.opacity)

          detail
            .font(.caption)
            .opacity(0.85)
            .lineLimit(1)
            .contentTransition(.opacity)
        }

        if isResolving {
          ProgressView()
            .controlSize(.small)
            #if !os(tvOS)
              .tint(Color.prominentButtonForeground)
            #endif
            .padding(.leading, 4)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 12)
    }
    .adaptiveButtonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    // Text(verbatim:) keeps the separator out of string extraction.
    .accessibilityLabel(Text(label) + Text(verbatim: ", ") + detail)
  }
}
