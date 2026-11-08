import SwiftUI

#if os(iOS)
  /// The owning Form applies `.mangaToolsSheets(model:)` with the same model.
  struct PanelModeSettingsSection: View {
    let model: MangaToolsSettingsModel

    @AppStorage("panelZoomFillFactor") private var panelZoomFillFactor: Double = 0.9
    @AppStorage("activePanelModelVersion") private var activePanelModelVersion: String?

    var body: some View {
      Section(
        header: Text("Panel Mode"),
        footer: Text("Use the Panel Mode button in the reader controls. Page-turn taps move between panels.")
      ) {
        Button {
          model.sheet = .panelModel
        } label: {
          HStack {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text("Panel Mode Model")
                Text(
                  activePanelModelVersion == nil
                    ? String(localized: "Not Downloaded")
                    : PanelModelLibrary.installedArchive()?.name ?? String(localized: "Not Downloaded")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
              }
            } icon: {
              Image(systemName: "rectangle.split.2x2")
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Panel Zoom Fill")
            Spacer()
            Text(String(format: "%.0f%%", panelZoomFillFactor * 100))
              .foregroundColor(.secondary)
          }
          Slider(value: $panelZoomFillFactor, in: 0.75...1.0, step: 0.05)
          Text(
            "Choose how much of the screen a focused panel fills; the remainder keeps neighboring panels visible."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
    }
  }
#endif
