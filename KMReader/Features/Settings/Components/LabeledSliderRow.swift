//
//  LabeledSliderRow.swift
//
//

#if os(iOS) || os(macOS)
  import SwiftUI

  /// Label + trailing value on top, slider below, so the current value stays
  /// visible while dragging.
  struct LabeledSliderRow: View {
    let label: String
    let value: String
    var binding: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double

    init(label: String, value: String, binding: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
      self.label = label
      self.value = value
      self.binding = binding
      self.range = range
      self.step = step
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(label)
          Spacer()
          Text(value)
            .foregroundColor(.secondary)
        }
        Slider(value: binding, in: range, step: step)
      }
    }
  }
#endif
