//
// OpenSourceLicenseDetailView.swift
//
//

import SwiftUI

struct OpenSourceLicenseDetailView: View {
  let license: OpenSourceLicense

  var body: some View {
    List {
      Section {
        HStack {
          Text(String(localized: "License"))
          Spacer()
          Text(license.license)
            .foregroundColor(.secondary)
        }

        Link(destination: license.sourceURL) {
          HStack {
            Label(String(localized: "Source Code"), systemImage: "chevron.left.forwardslash.chevron.right")
            Spacer()
            Image(systemName: AppIcon.externalLink)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Section(header: Text(String(localized: "Notice"))) {
        Text(license.notice)
          .font(.footnote.monospaced())
          .textSelectionIfAvailable()
      }
    }
    .platformNavigationTitle(license.name)
  }
}
