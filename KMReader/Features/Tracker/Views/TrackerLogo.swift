//
// TrackerLogo.swift
//

import SwiftUI

struct TrackerLogo: View {
  let provider: TrackerProvider

  var body: some View {
    Image(provider.imageName)
      .resizable()
      .scaledToFit()
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .accessibilityHidden(true)
  }
}
