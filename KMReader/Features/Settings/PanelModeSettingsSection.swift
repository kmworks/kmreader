import SwiftUI

#if os(iOS)
  struct PanelModeSettingsSection: View {
    @AppStorage("panelZoomFillFactor") private var panelZoomFillFactor: Double = 0.9
    @AppStorage("activePanelModelVersion") private var activePanelModelVersion: String?
    @State private var showsPanelModelManagement = false

    var body: some View {
      Section(
        header: Text("Panel Mode"),
        footer: Text("Use the Panel Mode button in the reader controls. Page-turn taps move between panels.")
      ) {
        Button {
          showsPanelModelManagement = true
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
      .sheet(isPresented: $showsPanelModelManagement) {
        SheetView(title: String(localized: "Panel Mode Model"), size: .large, applyFormStyle: true) {
          PanelModelManagementView()
        }
      }
    }
  }
#endif
