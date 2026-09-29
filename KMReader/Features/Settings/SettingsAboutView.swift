import SwiftUI

struct SettingsAboutView: View {
  @State private var showSubscription = false

  private var isSupporter: Bool {
    StoreManager.shared.hasActiveSubscription
  }

  var body: some View {
    Form {
      Section {
        Button {
          showSubscription = true
        } label: {
          HStack {
            if isSupporter {
              Label(String(localized: "Thanks for Support"), systemImage: "heart.fill")
                .foregroundColor(.pink)
            } else {
              Label(String(localized: "Buy Me a Coffee"), systemImage: "cup.and.saucer.fill")
            }
            Spacer()
            if isSupporter {
              Text("☕️")
            } else {
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showSubscription) {
          SubscriptionView()
        }

        if let privacyURL = URL(string: "https://kmworks.date/reader/privacy/") {
          Link(destination: privacyURL) {
            HStack {
              Label(String(localized: "Privacy Policy"), systemImage: "hand.raised")
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        if let termsURL = URL(
          string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        ) {
          Link(destination: termsURL) {
            HStack {
              Label(String(localized: "Terms of Use"), systemImage: "doc.text")
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        if let reviewURL = URL(string: "https://apps.apple.com/app/id6755198424?action=write-review") {
          Link(destination: reviewURL) {
            HStack {
              Label(String(localized: "Rate This App"), systemImage: "star")
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        if let feedbackURL = URL(string: "https://github.com/kmworks/kmreader/issues") {
          Link(destination: feedbackURL) {
            HStack {
              Label(String(localized: "Feedback"), systemImage: "paperplane")
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        if let sourceURL = URL(string: "https://github.com/kmworks/kmreader") {
          Link(destination: sourceURL) {
            HStack {
              Label(
                String(localized: "Source Code"),
                systemImage: "chevron.left.forwardslash.chevron.right"
              )
              Spacer()
              Image(systemName: "arrow.up.right.square")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        NavigationLink {
          OpenSourceLicensesView()
        } label: {
          Label(String(localized: "Open Source Licenses"), systemImage: "doc.plaintext")
        }

        HStack {
          Spacer()
          Text(Bundle.main.appVersion)
            .foregroundColor(.secondary)
          Spacer()
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(String(localized: "About"))
  }
}
