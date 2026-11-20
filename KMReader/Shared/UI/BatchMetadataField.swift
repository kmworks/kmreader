//
// BatchMetadataField.swift
//
//

import SwiftUI

struct BatchMetadataField<Content: View>: View {
  let title: String
  let hint: String?
  @Binding var isEnabled: Bool
  @Binding var isLocked: Bool
  let content: Content

  init(
    title: String,
    hint: String? = nil,
    isEnabled: Binding<Bool>,
    isLocked: Binding<Bool>,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.hint = hint
    _isEnabled = isEnabled
    _isLocked = isLocked
    self.content = content()
  }

  var body: some View {
    Section {
      Toggle(title, isOn: $isEnabled)
      if isEnabled {
        content
          .lockToggle(isLocked: $isLocked, alignment: .top)
        if let hint {
          Text(hint)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
