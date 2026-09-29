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
              HStack {
                Label("Version", systemImage: "number")
                Spacer()
                Text(version)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let artifact = build.artifact {
              HStack {
                Label("Artifact", systemImage: "cube.box")
                Spacer()
                Text(artifact)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let name = build.name {
              HStack {
                Label("Name", systemImage: "tag")
                Spacer()
                Text(name)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let group = build.group {
              HStack {
                Label("Group", systemImage: "folder")
                Spacer()
                Text(group)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let time = build.time {
              HStack {
                Label("Build Time", systemImage: "clock")
                Spacer()
                Text(time)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
          }
        }

        if let git = serverInfo.git {
          Section(header: Text("Git Information")) {
            if let branch = git.branch {
              HStack {
                Label("Branch", systemImage: "arrow.branch")
                Spacer()
                Text(branch)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let commit = git.commit {
              if let id = commit.id {
                HStack {
                  Label("Commit ID", systemImage: "number.square")
                  Spacer()
                  Text(id)
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
                }
                .tvFocusableHighlight()
              }
              if let idAbbrev = commit.idAbbrev {
                HStack {
                  Label("Commit ID (Short)", systemImage: "number.square.fill")
                  Spacer()
                  Text(idAbbrev)
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
                }
                .tvFocusableHighlight()
              }
              if let time = commit.time {
                HStack {
                  Label("Commit Time", systemImage: "clock")
                  Spacer()
                  Text(time)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }
          }
        }

        if let java = serverInfo.java {
          Section(header: Text("Java Information")) {
            if let version = java.version {
              HStack {
                Label("Version", systemImage: "number")
                Spacer()
                Text(version)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let vendor = java.vendor {
              if let name = vendor.name {
                HStack {
                  Label("Vendor", systemImage: "building.2")
                  Spacer()
                  Text(name)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
              if let version = vendor.version {
                HStack {
                  Label("Vendor Version", systemImage: "tag")
                  Spacer()
                  Text(version)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }
            if let runtime = java.runtime {
              if let name = runtime.name {
                HStack {
                  Label("Runtime", systemImage: "gearshape")
                  Spacer()
                  Text(name)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
              if let version = runtime.version {
                HStack {
                  Label("Runtime Version", systemImage: "number.square")
                  Spacer()
                  Text(version)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }
            if let jvm = java.jvm {
              if let name = jvm.name {
                HStack {
                  Label("JVM", systemImage: "cpu")
                  Spacer()
                  Text(name)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
              if let vendor = jvm.vendor {
                HStack {
                  Label("JVM Vendor", systemImage: "building.2")
                  Spacer()
                  Text(vendor)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
              if let version = jvm.version {
                HStack {
                  Label("JVM Version", systemImage: "number.square")
                  Spacer()
                  Text(version)
                    .foregroundColor(.secondary)
                }
                .tvFocusableHighlight()
              }
            }
          }
        }

        if let os = serverInfo.os {
          Section(header: Text("Operating System")) {
            if let name = os.name {
              HStack {
                Label("Name", systemImage: "desktopcomputer")
                Spacer()
                Text(name)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let version = os.version {
              HStack {
                Label("Version", systemImage: "number")
                Spacer()
                Text(version)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
            }
            if let arch = os.arch {
              HStack {
                Label("Architecture", systemImage: "cpu")
                Spacer()
                Text(arch)
                  .foregroundColor(.secondary)
              }
              .tvFocusableHighlight()
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
