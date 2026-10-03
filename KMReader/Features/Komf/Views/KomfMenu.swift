//
// KomfMenu.swift
//
//

import SwiftUI

/// The shared Komf submenu used by detail-page ellipsis menus and the series
/// context menu. Reset is offered only where a confirmation alert exists.
struct KomfMenu: View {
  let libraryId: String
  let seriesId: String
  let seriesTitle: String
  let onIdentify: () -> Void
  var onReset: (() -> Void)? = nil

  @State private var isSubmitting = false

  var body: some View {
    Menu {
      Button {
        deferMenuActionPresentation { onIdentify() }
      } label: {
        Label("Identify", systemImage: "sparkles")
      }

      Button {
        match()
      } label: {
        Label("Match", systemImage: "arrow.triangle.2.circlepath")
      }

      if let onReset {
        Button {
          deferMenuActionPresentation { onReset() }
        } label: {
          Label("Reset Metadata", systemImage: "arrow.counterclockwise")
        }
      }
    } label: {
      Label(title: { Text(verbatim: "Komf") }, icon: { Image(systemName: "sparkles") })
    }
    .disabled(isSubmitting)
  }

  private func match() {
    isSubmitting = true
    Task {
      defer { isSubmitting = false }
      await KomfActions.match(
        libraryId: libraryId, seriesId: seriesId, seriesTitle: seriesTitle)
    }
  }
}
