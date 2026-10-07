//
// ServerInfoView.swift
//
//

import SwiftUI

/// Server overview. On kmrs the stats endpoint answers process, totals, and
/// task metrics in one request; elsewhere (Komga) the same rows are filled
/// from the actuator metrics one by one. Servers without `/actuator/info`
/// get the unavailable state; task queue, sessions, and scheduled tasks live
/// in the sub-pages.
struct ServerInfoView: View {
  @AppStorage("currentAccount") private var current: Current = .init()
  @AppStorage("isOffline") private var isOffline: Bool = false
  @AppStorage("taskQueueStatus") private var taskQueueStatus: TaskQueueSSEDto = TaskQueueSSEDto()

  @State private var serverInfo: ActuatorInfoResponse?
  @State private var process = ProcessInfo()
  @State private var content = ContentCounts()
  @State private var isLoading = false
  @State private var isUnsupported = false
  @State private var loadedInstanceId: String?
  @State private var logfileAvailable = false
  @State private var showShutdownConfirmation = false
  @State private var isShuttingDown = false
  @State private var isDownloadingLogs = false

  var body: some View {
    Form {
      if !current.isAdmin {
        AdminRequiredView()
      } else if isLoading && serverInfo == nil && !isUnsupported {
        Section {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      } else if isUnsupported {
        Section {
          ContentUnavailableView {
            Label(
              String(localized: "Server Info Unavailable"),
              systemImage: ServerSection.serverInfo.icon)
          } description: {
            Text(String(localized: "This server does not provide server statistics."))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        }
      } else if isOffline && serverInfo == nil {
        Section {
          ContentUnavailableView {
            Label(
              String(localized: "Server Info Unavailable"),
              systemImage: ServerSection.serverInfo.icon)
          } description: {
            Text(String(localized: "Server info requires an online connection."))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
        }
      } else {
        if serverInfo != nil || process.hasAnyValue {
          Section(header: Text(String(localized: "Server"))) {
            if let version = serverInfo?.build?.version {
              infoRow(String(localized: "Version"), version, "tag")
            }
            if let commit = commitDescription {
              infoRow(String(localized: "Commit"), commit, "arrow.triangle.branch", monospaced: true)
            }
            if let os = osDescription {
              infoRow(String(localized: "OS"), os, "desktopcomputer")
            }
            if let startTime = process.startTime {
              infoRow(
                String(localized: "Start Time"),
                startTime.formatted(date: .abbreviated, time: .shortened),
                "clock")
            }
            if let uptimeSeconds = process.uptimeSeconds {
              infoRow(
                String(localized: "Uptime"),
                Self.formatDuration(seconds: uptimeSeconds),
                "timer")
            }
          }
        }

        if process.cpuPercent != nil || process.memoryBytes != nil || process.diskFreeBytes != nil {
          Section(header: Text(String(localized: "Resources"))) {
            if let cpuPercent = process.cpuPercent {
              infoRow(
                String(localized: "CPU Usage"),
                String(format: "%.1f %%", cpuPercent),
                "cpu")
            }
            if let memoryBytes = process.memoryBytes {
              infoRow(
                String(localized: "Memory"),
                memoryBytes.humanReadableFileSize,
                "memorychip")
            }
            if let diskFreeBytes = process.diskFreeBytes {
              let value =
                if let diskTotalBytes = process.diskTotalBytes {
                  String.localizedStringWithFormat(
                    String(
                      localized: "server.info.diskFreeOfTotal",
                      defaultValue: "%@ free of %@"),
                    diskFreeBytes.humanReadableFileSize, diskTotalBytes.humanReadableFileSize)
                } else {
                  String.localizedStringWithFormat(
                    String(
                      localized: "server.info.diskFree",
                      defaultValue: "%@ free"),
                    diskFreeBytes.humanReadableFileSize)
                }
              infoRow(String(localized: "Disk"), value, "internaldrive")
            }
          }
        }

        if content.hasAnyValue {
          Section(header: Text(String(localized: "Content"))) {
            if let libraries = content.libraries {
              infoRow(String(localized: "Libraries"), "\(Int(libraries))", ContentIcon.library)
            }
            if let series = content.series {
              infoRow(String(localized: "Series"), "\(Int(series))", ContentIcon.series)
            }
            if let books = content.books {
              infoRow(String(localized: "Books"), "\(Int(books))", ContentIcon.book)
            }
            if let collections = content.collections {
              infoRow(
                String(localized: "Collections"), "\(Int(collections))", ContentIcon.collection)
            }
            if let readlists = content.readlists {
              infoRow(
                String(localized: "Read Lists"), "\(Int(readlists))", ContentIcon.readList)
            }
            if let sidecars = content.sidecars {
              infoRow(
                String(localized: "Sidecars"), "\(Int(sidecars))", "doc.badge.gearshape")
            }
            if let fileSize = content.fileSize {
              infoRow(
                String(localized: "Total Size"),
                fileSize.humanReadableFileSize,
                "archivebox")
            }
          }
        }

        Section {
          NavigationLink(value: NavDestination.settingsServerTasks) {
            HStack {
              Label(String(localized: "Tasks"), systemImage: "list.bullet.clipboard")
              Spacer()
              if taskQueueStatus.count > 0 {
                Text("\(taskQueueStatus.count)")
                  .foregroundColor(.secondary)
                  .contentTransition(.numericText())
              }
            }
          }
          NavigationLink(value: NavDestination.settingsServerSessions) {
            Label(String(localized: "Sessions"), systemImage: "person.2")
          }
          NavigationLink(value: NavDestination.settingsServerScheduledTasks) {
            Label(String(localized: "Scheduled Tasks"), systemImage: "calendar.badge.clock")
          }
        }

        Section(header: Text(String(localized: "Maintenance"))) {
          #if os(iOS) || os(macOS)
            if logfileAvailable {
              Button {
                downloadLogFile()
              } label: {
                HStack {
                  Label(String(localized: "Download Log File"), systemImage: "doc.text")
                  Spacer()
                  if isDownloadingLogs {
                    ProgressView()
                  }
                }
                .contentShape(Rectangle())
              }
              .disabled(isDownloadingLogs)
              .tvFocusableHighlight()
            }
          #endif

          Button(role: .destructive) {
            showShutdownConfirmation = true
          } label: {
            HStack {
              Label(String(localized: "Shut Down Server"), systemImage: "power")
              Spacer()
              if isShuttingDown {
                ProgressView()
              }
            }
            .contentShape(Rectangle())
          }
          .disabled(isShuttingDown)
          .tvFocusableHighlight()
        }
      }
    }
    .formStyle(.grouped)
    .platformNavigationTitle(ServerSection.serverInfo.title)
    .alert(String(localized: "Shut Down Server"), isPresented: $showShutdownConfirmation) {
      Button(String(localized: "Cancel"), role: .cancel) {}
      Button(String(localized: "Shut Down"), role: .destructive) {
        shutdownServer()
      }
    } message: {
      Text(
        String(
          localized: "The server will shut down and become unreachable until it is restarted.")
      )
    }
    .task {
      // .task re-fires when a sub-page pops back; only reload for a new instance.
      if current.isAdmin, loadedInstanceId != current.instanceId {
        await loadServerInfo()
      }
    }
    .onChange(of: isOffline) { oldValue, newValue in
      if oldValue && !newValue && current.isAdmin {
        Task {
          await loadServerInfo()
        }
      }
    }
    .refreshable {
      if current.isAdmin {
        await loadServerInfo()
      }
    }
  }

  private var commitDescription: String? {
    guard let git = serverInfo?.git else { return nil }
    let parts = [git.branch, git.commit?.id].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private var osDescription: String? {
    guard let os = serverInfo?.os else { return nil }
    let parts = [os.name, os.version, os.arch].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }

  static func formatDuration(seconds: Double) -> String {
    Duration.seconds(seconds)
      .formatted(
        .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2)
      )
  }

  private func infoRow(_ label: String, _ value: String, _ icon: String, monospaced: Bool = false)
    -> some View
  {
    InfoRow(label: label, value: value, icon: icon, monospaced: monospaced)
      .tvFocusableHighlight()
  }

  private func loadServerInfo() async {
    guard !AppConfig.isOffline else { return }
    isLoading = true

    do {
      serverInfo = try await ManagementService.getInfo()
      isUnsupported = false
    } catch let error as APIError {
      if case .notFound = error {
        isUnsupported = true
      } else {
        ErrorManager.shared.alert(error: error)
      }
      isLoading = false
      return
    } catch {
      ErrorManager.shared.alert(error: error)
      isLoading = false
      return
    }

    #if os(iOS) || os(macOS)
      async let logfileProbe = Self.probeLogfile()
    #endif
    async let healthRequest = Self.loadHealth()

    do {
      if let stats = try await ServerStatsService.getServerStatsIfSupported(
        instanceId: current.instanceId)
      {
        process = ProcessInfo(
          startTime: Self.startTimeFormatter.date(from: stats.process.startTime),
          uptimeSeconds: stats.process.uptimeSeconds,
          cpuPercent: stats.process.cpuUsage,
          memoryBytes: stats.process.memoryBytes
        )
        content = ContentCounts(
          libraries: stats.totals.libraries,
          series: stats.totals.series,
          books: stats.totals.books,
          collections: stats.totals.collections,
          readlists: stats.totals.readlists,
          sidecars: stats.totals.sidecars,
          fileSize: stats.totals.fileSize
        )
      } else {
        await loadActuatorFallback()
      }
    } catch {
      ErrorManager.shared.alert(error: error)
    }

    if let health = await healthRequest {
      process.diskFreeBytes = health.components?.diskSpace?.details?.free
      process.diskTotalBytes = health.components?.diskSpace?.details?.total
    }
    #if os(iOS) || os(macOS)
      logfileAvailable = await logfileProbe
    #endif
    loadedInstanceId = current.instanceId
    isLoading = false
  }

  /// Komga path: the same rows one actuator metric at a time.
  private func loadActuatorFallback() async {
    do {
      async let cpuRequest = ManagementService.getMetricOptional("process.cpu.usage")
      async let memoryRequest = ManagementService.getMetricOptional("jvm.memory.used")
      async let uptimeRequest = ManagementService.getMetricOptional("process.uptime")
      async let startRequest = ManagementService.getMetricOptional("process.start.time")
      async let librariesRequest = ManagementService.getMetricOptional("komga.libraries")
      async let seriesRequest = ManagementService.getMetricOptional("komga.series")
      async let booksRequest = ManagementService.getMetricOptional("komga.books")
      async let collectionsRequest = ManagementService.getMetricOptional("komga.collections")
      async let readlistsRequest = ManagementService.getMetricOptional("komga.readlists")
      async let sidecarsRequest = ManagementService.getMetricOptional("komga.sidecars")
      async let fileSizeRequest = ManagementService.getMetricOptional("komga.books.filesize")

      let (cpu, memory, uptime, start) = try await (cpuRequest, memoryRequest, uptimeRequest, startRequest)
      process = ProcessInfo(
        startTime: start?.value("VALUE").map { Date(timeIntervalSince1970: $0 / 1000) },
        uptimeSeconds: uptime?.value("VALUE"),
        cpuPercent: cpu.flatMap(Self.cpuPercent),
        memoryBytes: memory?.value("VALUE")
      )

      let gauges = try await (
        librariesRequest, seriesRequest, booksRequest, collectionsRequest, readlistsRequest,
        sidecarsRequest, fileSizeRequest
      )
      content = ContentCounts(
        libraries: gauges.0?.value("VALUE"),
        series: gauges.1?.value("VALUE"),
        books: gauges.2?.value("VALUE"),
        collections: gauges.3?.value("VALUE"),
        readlists: gauges.4?.value("VALUE"),
        sidecars: gauges.5?.value("VALUE"),
        fileSize: gauges.6?.value("VALUE")
      )
    } catch {
      ErrorManager.shared.alert(error: error)
    }
  }

  /// kmrs reports percent directly; Spring's gauge is a 0-1 ratio with no
  /// base unit (and -1 while unavailable).
  private static func cpuPercent(from metric: Metric) -> Double? {
    guard let value = metric.value("VALUE"), value >= 0 else { return nil }
    return metric.baseUnit == "percent" ? value : value * 100
  }

  private static func loadHealth() async -> ActuatorHealthResponse? {
    do {
      return try await ManagementService.getHealth()
    } catch let error as APIError {
      if case .notFound = error { return nil }
      ErrorManager.shared.alert(error: error)
      return nil
    } catch {
      ErrorManager.shared.alert(error: error)
      return nil
    }
  }

  /// A probe failure keeps the button visible; the download surfaces errors.
  private static func probeLogfile() async -> Bool {
    do {
      return try await ManagementService.isLogfileAvailable()
    } catch {
      return true
    }
  }

  private func shutdownServer() {
    guard !isShuttingDown else { return }
    isShuttingDown = true
    Task {
      do {
        try await ManagementService.shutdown()
        ErrorManager.shared.notify(message: String(localized: "notification.server.shuttingDown"))
      } catch {
        ErrorManager.shared.alert(error: error)
      }
      isShuttingDown = false
    }
  }

  #if os(iOS) || os(macOS)
    private func downloadLogFile() {
      guard !isDownloadingLogs else { return }
      isDownloadingLogs = true
      Task {
        do {
          let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("server.log")
          try await ManagementService.downloadLogFile(destinationURL: destinationURL)
          ShareHelper.share(items: [destinationURL])
        } catch {
          ErrorManager.shared.alert(error: error)
        }
        isDownloadingLogs = false
      }
    }
  #endif

  private static let startTimeFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private struct ProcessInfo {
    var startTime: Date?
    var uptimeSeconds: Double?
    var cpuPercent: Double?
    var memoryBytes: Double?
    var diskFreeBytes: Double?
    var diskTotalBytes: Double?

    var hasAnyValue: Bool {
      startTime != nil || uptimeSeconds != nil || cpuPercent != nil || memoryBytes != nil
    }
  }

  private struct ContentCounts {
    var libraries: Double?
    var series: Double?
    var books: Double?
    var collections: Double?
    var readlists: Double?
    var sidecars: Double?
    var fileSize: Double?

    var hasAnyValue: Bool {
      libraries != nil || series != nil || books != nil || collections != nil || readlists != nil
        || sidecars != nil || fileSize != nil
    }
  }
}
