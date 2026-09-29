//
// OpenSourceLicensesView.swift
//
//

import SwiftUI

struct OpenSourceLicensesView: View {
  private let licenses = OpenSourceLicenseStore.load()

  var body: some View {
    List {
      if licenses.isEmpty {
        Text(String(localized: "settings.licenses.empty"))
          .foregroundColor(.secondary)
      } else {
        Section(header: Text(String(localized: "settings.licenses.description"))) {
          ForEach(licenses) { license in
            NavigationLink {
              OpenSourceLicenseDetailView(license: license)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(license.name)
                Text(license.license)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        }
      }
    }
    .platformNavigationTitle(String(localized: "Open Source Licenses"))
  }
}
