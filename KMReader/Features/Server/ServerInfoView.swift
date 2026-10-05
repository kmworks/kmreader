//
// ServerInfoView.swift
//
//

import SwiftUI

struct ServerInfoView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var serverInfo: ServerInfo?
  @State private var isLoading = false

  private struct InfoSectionData {
    let title: LocalizedStringKey
    let rows: [InfoRowData]
  }

  private struct InfoRowData {
    let label: String.LocalizationValue
    let value: String
    let icon: String
    var monospaced: Bool = false
  }

  var body: some View {
    Form {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if serverInfo != nil {
        if infoSections.isEmpty {
          Section {
            HStack {
              Spacer()
              Text("No server information available")
                .foregroundColor(.secondary)
              Spacer()
            }
            .tvFocusableHighlight()
          }
        } else {
          ForEach(Array(infoSections.enumerated()), id: \.offset) { _, section in
            Section(header: Text(section.title)) {
              ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                infoRow(data: row)
              }
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(ServerSection.serverInfo.title)
    .task {
      if current.isAdmin {
        await loadServerInfo()
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadServerInfo()
      }
    }
  }

  private var infoSections: [InfoSectionData] {
    guard let serverInfo else { return [] }
    var sections: [InfoSectionData] = []

    if let build = serverInfo.build {
      let rows = [
        infoRowData("Version", build.version, "number"),
        infoRowData("Artifact", build.artifact, "cube.box"),
        infoRowData("Name", build.name, "tag"),
        infoRowData("Group", build.group, "folder"),
        infoRowData("Build Time", build.time, "clock"),
      ].compactMap { $0 }
      if !rows.isEmpty {
        sections.append(InfoSectionData(title: "Build Information", rows: rows))
      }
    }

    if let git = serverInfo.git {
      var rows: [InfoRowData?] = [
        infoRowData("Branch", git.branch, "arrow.branch")
      ]
      if let commit = git.commit {
        rows.append(infoRowData("Commit ID", commit.id, "number.square", monospaced: true))
        rows.append(
          infoRowData(
            "Commit ID (Short)", commit.idAbbrev, "number.square.fill", monospaced: true))
        rows.append(infoRowData("Commit Time", commit.time, "clock"))
      }
      let compactRows = rows.compactMap { $0 }
      if !compactRows.isEmpty {
        sections.append(InfoSectionData(title: "Git Information", rows: compactRows))
      }
    }

    if let java = serverInfo.java {
      var rows: [InfoRowData?] = [
        infoRowData("Version", java.version, "number")
      ]
      if let vendor = java.vendor {
        rows.append(infoRowData("Vendor", vendor.name, "building.2"))
        rows.append(infoRowData("Vendor Version", vendor.version, "tag"))
      }
      if let runtime = java.runtime {
        rows.append(infoRowData("Runtime", runtime.name, "gearshape"))
        rows.append(infoRowData("Runtime Version", runtime.version, "number.square"))
      }
      if let jvm = java.jvm {
        rows.append(infoRowData("JVM", jvm.name, "cpu"))
        rows.append(infoRowData("JVM Vendor", jvm.vendor, "building.2"))
        rows.append(infoRowData("JVM Version", jvm.version, "number.square"))
      }
      let compactRows = rows.compactMap { $0 }
      if !compactRows.isEmpty {
        sections.append(InfoSectionData(title: "Java Information", rows: compactRows))
      }
    }

    if let os = serverInfo.os {
      let rows = [
        infoRowData("Name", os.name, "desktopcomputer"),
        infoRowData("Version", os.version, "number"),
        infoRowData("Architecture", os.arch, "cpu"),
      ].compactMap { $0 }
      if !rows.isEmpty {
        sections.append(InfoSectionData(title: "Operating System", rows: rows))
      }
    }

    return sections
  }

  /// kmrs keeps the Spring `java` section's shape with "-" placeholders; treat
  /// placeholder and blank values as absent so empty sections hide entirely.
  private func infoRowData(
    _ label: String.LocalizationValue,
    _ value: String?,
    _ icon: String,
    monospaced: Bool = false
  ) -> InfoRowData? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed != "-" else { return nil }
    return InfoRowData(label: label, value: value, icon: icon, monospaced: monospaced)
  }

  private func infoRow(data: InfoRowData) -> some View {
    InfoRow(
      label: String(localized: data.label),
      value: data.value,
      icon: data.icon,
      monospaced: data.monospaced
    )
    .tvFocusableHighlight()
  }

  private func loadServerInfo() async {
    isLoading = true

    do {
      serverInfo = try await ManagementService.getActuatorInfo()
    } catch {
      ErrorManager.shared.alert(error: error)
    }

    isLoading = false
  }
}
