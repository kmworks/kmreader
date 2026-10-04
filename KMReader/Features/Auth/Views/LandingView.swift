//
// LandingView.swift
//
//

import SwiftUI

struct LandingView: View {
  let authViewModel: AuthViewModel
  @State private var showGetStarted = false

  var body: some View {
    VStack(spacing: 40) {
      Spacer()

      // Logo
      Image(AppIconLogoAsset.current)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: 120)

      // App Name
      Text("KMReader")
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(.primary)

      // Tagline
      Text("Your Komga library, ready to read")
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)

      Spacer()

      // Get Started Button
      Button(action: {
        showGetStarted = true
      }) {
        HStack(spacing: 8) {
          Text("Get Started")
            .fontWeight(.semibold)
          Image(systemName: "arrow.right")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
      }
      .adaptiveButtonStyle(.borderedProminent)
      .padding(.horizontal, 24)
      .frame(maxWidth: 360)
      .padding(.bottom, 40)
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $showGetStarted) {
        SheetView(title: "Get Started") {
          ServerListView(authViewModel: authViewModel, mode: .onboarding)
        }
      }
    #else
      .sheet(isPresented: $showGetStarted) {
        SheetView(title: "Get Started", applyFormStyle: true) {
          ServerListView(authViewModel: authViewModel, mode: .onboarding)
        }
      }
    #endif
  }
}

#Preview {
  LandingView(authViewModel: AuthViewModel())
}
