//
// NotableEntitiesEditor.swift
//

import SwiftUI

struct NotableEntitiesEditor: View {
  @Binding var entities: [NotableEntity]
  @Binding var isLocked: Bool

  @State private var newKind = "character"
  @State private var customKind = ""
  @State private var newName = ""

  var body: some View {
    Section {
      ForEach(entities.indices, id: \.self) { index in
        HStack {
          VStack(alignment: .leading) {
            Text(entities[index].name)
            Text(entities[index].kindDisplayName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button(role: .destructive) {
            let indexToRemove = index
            withAnimation {
              entities.remove(at: indexToRemove)
              isLocked = true
            }
          } label: {
            Image(systemName: AppIcon.delete)
              .padding(8)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(Text("Delete"))
        }
      }
      Picker(String(localized: "Kind"), selection: $newKind) {
        ForEach(NotableEntity.knownKinds, id: \.self) { kind in
          Text(NotableEntity.kindDisplayName(kind)).tag(kind)
        }
        Text(String(localized: "Custom")).tag("custom")
      }
      if newKind == "custom" {
        TextField(String(localized: "Custom Kind"), text: $customKind)
          #if os(iOS) || os(tvOS)
            .autocapitalization(.none)
          #endif
      }
      TextField(String(localized: "Name"), text: $newName)
        .onSubmit(addEntity)
      Button(action: addEntity) {
        Label(String(localized: "Add Notable Entity"), systemImage: AppIcon.addRow)
          .frame(maxWidth: .infinity)
      }
      .adaptiveButtonStyle(hasPendingEntity ? .borderedProminent : .borderless)
      .disabled(!hasPendingEntity)
      .opacity(hasPendingEntity ? 1 : 0.5)
    } header: {
      Text(String(localized: "Notable Entities"))
        .lockToggle(isLocked: $isLocked)
    }
  }

  private var hasPendingEntity: Bool {
    !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (newKind != "custom"
        || !customKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func addEntity() {
    guard hasPendingEntity else { return }
    let kind = newKind == "custom" ? customKind : newKind
    let entity = NotableEntity(kind: kind, name: newName)
    withAnimation {
      entities.append(entity)
      isLocked = true
      newName = ""
      customKind = ""
    }
  }
}
