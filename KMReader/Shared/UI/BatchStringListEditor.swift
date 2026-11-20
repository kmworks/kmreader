//
// BatchStringListEditor.swift
//
//

import SwiftUI

struct BatchStringListEditor: View {
  let placeholder: String
  @Binding var values: [String]
  @State private var newValue = ""

  private var hasPendingValue: Bool {
    !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(values.indices, id: \.self) { index in
        HStack {
          Text(values[index])
          Spacer()
          Button(role: .destructive) {
            values.remove(at: index)
          } label: {
            Image(systemName: AppIcon.delete)
          }
          // Keep the destructive action from taking the whole Form row's tap.
          .adaptiveButtonStyle(.borderless)
        }
      }

      HStack {
        TextField(placeholder, text: $newValue)
          .onSubmit(addValue)
        Button(action: addValue) {
          Image(systemName: AppIcon.addRow)
        }
        .adaptiveButtonStyle(.borderless)
        .disabled(!hasPendingValue)
      }
    }
  }

  private func addValue() {
    let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !values.contains(value) else { return }
    values.append(value)
    newValue = ""
  }
}
