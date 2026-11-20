//
// BatchPairListEditor.swift
//
//

import SwiftUI

struct BatchPairListEditor: View {
  let firstPlaceholder: String
  let secondPlaceholder: String
  let addLabel: String
  @Binding var pairs: [BatchMetadataPair]
  @State private var first = ""
  @State private var second = ""

  private var hasPendingPair: Bool {
    !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(pairs) { pair in
        HStack(alignment: .top) {
          VStack(alignment: .leading) {
            Text(pair.first)
            Text(pair.second)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button(role: .destructive) {
            pairs.removeAll { $0.id == pair.id }
          } label: {
            Image(systemName: AppIcon.delete)
          }
          // Keep the destructive action from taking the whole Form row's tap.
          .adaptiveButtonStyle(.borderless)
        }
      }

      TextField(firstPlaceholder, text: $first)
        .onSubmit(addPair)
      TextField(secondPlaceholder, text: $second)
        .onSubmit(addPair)
      Button(action: addPair) {
        Label(addLabel, systemImage: AppIcon.addRow)
      }
      .adaptiveButtonStyle(hasPendingPair ? .borderedProminent : .borderless)
      .disabled(!hasPendingPair)
    }
  }

  private func addPair() {
    let trimmedFirst = first.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSecond = second.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedFirst.isEmpty, !trimmedSecond.isEmpty else { return }
    pairs.append(BatchMetadataPair(first: trimmedFirst, second: trimmedSecond))
    first = ""
    second = ""
  }
}
