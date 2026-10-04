//
// ServerInfoView.swift
//
//

import SwiftUI

struct ServerInfoView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @State private var serverInfo: ServerInfo?
  @State private var isLoading = false

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
      } else if let serverInfo = serverInfo {
        if let build = serverInfo.build {
          Section(header: Text("Build Information")) {
            if let version = build.version {
              infoRow(label: "Version", value: version, icon: "number")
            }
            if let artifact = build.artifact {
              infoRow(label: "Artifact", value: artifact, icon: "cube.box")
            }
            if let name = build.name {
              infoRow(label: "Name", value: name, icon: "tag")
            }
            if let group = build.group {
              infoRow(label: "Group", value: group, icon: "folder")
            }
            if let time = build.time {
              infoRow(label: "Build Time", value: time, icon: "clock")
            }
          }
        }

        if let git = serverInfo.git {
          Section(header: Text("Git Information")) {
            if let branch = git.branch {
              infoRow(label: "Branch", value: branch, icon: "arrow.branch")
            }
            if let commit = git.commit {
              if let id = commit.id {
                infoRow(label: "Commit ID", value: id, icon: "number.square", monospaced: true)
              }
              if let idAbbrev = commit.idAbbrev {
                infoRow(
                  label: "Commit ID (Short)", value: idAbbrev, icon: "number.square.fill",
                  monospaced: true)
              }
              if let time = commit.time {
                infoRow(label: "Commit Time", value: time, icon: "clock")
              }
            }
          }
        }

        if let java = serverInfo.java {
          Section(header: Text("Java Information")) {
            if let version = java.version {
              infoRow(label: "Version", value: version, icon: "number")
            }
            if let vendor = java.vendor {
              if let name = vendor.name {
                infoRow(label: "Vendor", value: name, icon: "building.2")
              }
              if let version = vendor.version {
                infoRow(label: "Vendor Version", value: version, icon: "tag")
              }
            }
            if let runtime = java.runtime {
              if let name = runtime.name {
                infoRow(label: "Runtime", value: name, icon: "gearshape")
              }
              if let version = runtime.version {
                infoRow(label: "Runtime Version", value: version, icon: "number.square")
              }
            }
            if let jvm = java.jvm {
              if let name = jvm.name {
                infoRow(label: "JVM", value: name, icon: "cpu")
              }
              if let vendor = jvm.vendor {
                infoRow(label: "JVM Vendor", value: vendor, icon: "building.2")
              }
              if let version = jvm.version {
                infoRow(label: "JVM Version", value: version, icon: "number.square")
              }
            }
          }
        }

        if let os = serverInfo.os {
          Section(header: Text("Operating System")) {
            if let name = os.name {
              infoRow(label: "Name", value: name, icon: "desktopcomputer")
            }
            if let version = os.version {
              infoRow(label: "Version", value: version, icon: "number")
            }
            if let arch = os.arch {
              infoRow(label: "Architecture", value: arch, icon: "cpu")
            }
          }
        }

        if serverInfo.build == nil && serverInfo.git == nil && serverInfo.java == nil
          && serverInfo.os == nil
        {
          Section {
            HStack {
              Spacer()
              Text("No server information available")
                .foregroundColor(.secondary)
              Spacer()
            }
            .tvFocusableHighlight()
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

  private func infoRow(
    label: String.LocalizationValue, value: String, icon: String, monospaced: Bool = false
  ) -> some View {
    InfoRow(label: String(localized: label), value: value, icon: icon, monospaced: monospaced)
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
