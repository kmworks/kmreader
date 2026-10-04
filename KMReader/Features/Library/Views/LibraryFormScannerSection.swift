//
// LibraryFormScannerSection.swift
//
//

import SwiftUI

/// Scanner section of the library add/edit form: scan behavior, scan types,
/// oneshots directory, and directory exclusions.
struct LibraryFormScannerSection<Fields: LibraryFormFields>: View {
  @Binding var fields: Fields
  @Binding var newExclusion: String

  var body: some View {
    Section(header: Text(String(localized: "library.add.section.scanner", defaultValue: "Scanner"))) {
      Toggle(
        String(
          localized: "library.add.field.emptyTrashAfterScan", defaultValue: "Empty trash after scan"
        ),
        isOn: $fields.emptyTrashAfterScan
      )

      Toggle(
        String(
          localized: "library.add.field.scanForceModifiedTime",
          defaultValue: "Force directory modified time"),
        isOn: $fields.scanForceModifiedTime
      )

      Toggle(
        String(localized: "library.add.field.scanOnStartup", defaultValue: "Scan on startup"),
        isOn: $fields.scanOnStartup
      )

      Picker(
        String(localized: "library.add.field.scanInterval", defaultValue: "Scan interval"),
        selection: $fields.scanInterval
      ) {
        ForEach(ScanInterval.allCases) { interval in
          Text(interval.localizedName).tag(interval)
        }
      }

      Group {
        Toggle("CBX", isOn: $fields.scanCbx)
        Toggle("PDF", isOn: $fields.scanPdf)
        Toggle("EPUB", isOn: $fields.scanEpub)
      }

      TextField(
        String(
          localized: "library.add.field.oneshotsDirectory", defaultValue: "Oneshots directory"),
        text: $fields.oneshotsDirectory
      )

      VStack(alignment: .leading, spacing: 8) {
        Text(
          String(localized: "library.add.field.exclusions", defaultValue: "Directory exclusions")
        )
        .font(.subheadline)
        .foregroundColor(.secondary)

        ForEach(fields.scanDirectoryExclusions, id: \.self) { exclusion in
          HStack {
            Text(exclusion)
            Spacer()
            Button {
              fields.scanDirectoryExclusions.removeAll { $0 == exclusion }
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
          }
        }

        HStack {
          TextField(
            String(localized: "library.add.field.newExclusion", defaultValue: "Add exclusion"),
            text: $newExclusion
          )
          Button {
            guard !newExclusion.isEmpty else { return }
            fields.scanDirectoryExclusions.append(newExclusion)
            newExclusion = ""
          } label: {
            Image(systemName: "plus.circle.fill")
              .foregroundColor(.green)
          }
          .buttonStyle(.plain)
          .disabled(newExclusion.isEmpty)
        }
      }
    }
  }
}
