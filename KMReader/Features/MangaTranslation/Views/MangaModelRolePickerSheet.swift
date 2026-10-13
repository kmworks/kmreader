import SwiftUI

struct MangaModelRolePickerSheet: View {
  let role: MangaModelRole
  let archives: [ModelArchive]
  let selectedStorageKey: String
  let onSelect: (ModelArchive) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    SheetView(title: role.title, size: .large, applyFormStyle: true) {
      Form {
        Section {
          if archives.isEmpty {
            Text("No models downloaded")
              .foregroundStyle(.secondary)
          }
          ForEach(archives, id: \.storageKey) { archive in
            Button {
              onSelect(archive)
              dismiss()
            } label: {
              HStack(spacing: 12) {
                Image(systemName: selectedStorageKey == archive.storageKey ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(selectedStorageKey == archive.storageKey ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                  Text(archive.name)
                  if let comment = archive.comment, !comment.isEmpty {
                    Text(comment)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}
