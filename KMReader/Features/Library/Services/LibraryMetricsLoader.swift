//
// LibraryMetricsLoader.swift
//
//

import Foundation

struct LibraryMetricsLoader {
  static let shared = LibraryMetricsLoader()

  func refreshMetrics(
    instanceId: String,
    libraryIds: [String]
  ) async -> [String: LibraryMetricValues] {
    guard !instanceId.isEmpty else { return [:] }

    async let libraryMetrics = loadLibraryMetrics(for: libraryIds)
    await loadAllLibrariesMetrics(instanceId: instanceId)
    return await libraryMetrics
  }

  private func loadLibraryMetrics(for libraryIds: [String]) async -> [String: LibraryMetricValues] {
    guard !libraryIds.isEmpty else { return [:] }
    var metricsByLibrary: [String: LibraryMetricValues] = [:]

    await withTaskGroup(of: [(String, String, Double?)].self) { group in
      group.addTask {
        await self.processLibraryMetric(
          metricName: MetricName.booksFileSize.rawValue,
          libraryIds: libraryIds,
          key: "fileSize"
        )
      }
      group.addTask {
        await self.processLibraryMetric(
          metricName: MetricName.books.rawValue,
          libraryIds: libraryIds,
          key: "books"
        )
      }
      group.addTask {
        await self.processLibraryMetric(
          metricName: MetricName.series.rawValue,
          libraryIds: libraryIds,
          key: "series"
        )
      }
      group.addTask {
        await self.processLibraryMetric(
          metricName: MetricName.sidecars.rawValue,
          libraryIds: libraryIds,
          key: "sidecars"
        )
      }

      for await results in group {
        for (libraryId, key, value) in results {
          guard let value else { continue }
          if metricsByLibrary[libraryId] == nil {
            metricsByLibrary[libraryId] = LibraryMetricValues()
          }
          switch key {
          case "fileSize":
            metricsByLibrary[libraryId]?.fileSize = value
          case "books":
            metricsByLibrary[libraryId]?.booksCount = value
          case "series":
            metricsByLibrary[libraryId]?.seriesCount = value
          case "sidecars":
            metricsByLibrary[libraryId]?.sidecarsCount = value
          default:
            break
          }
        }
      }
    }

    return metricsByLibrary
  }

  private func processLibraryMetric(
    metricName: String,
    libraryIds: [String],
    key: String
  ) async -> [(String, String, Double?)] {
    guard let metric = try? await ManagementService.getMetric(metricName),
      let libraryTag = metric.availableTags?.first(where: { $0.tag == "library" })
    else {
      return []
    }

    var results: [(String, String, Double?)] = []

    for libraryId in libraryTag.values where libraryIds.contains(libraryId) {
      if let libraryMetric = try? await ManagementService.getMetric(
        metricName,
        tags: [MetricTag(key: "library", value: libraryId)]
      ),
        let value = libraryMetric.measurements.first(where: { $0.statistic == "VALUE" })?.value
      {
        results.append((libraryId, key, value))
      }
    }

    return results
  }

  private func loadAllLibrariesMetrics(instanceId: String) async {
    var metrics = AllLibrariesMetricsData()

    await withTaskGroup(of: (String, Double?).self) { group in
      group.addTask {
        if let metric = try? await ManagementService.getMetric(MetricName.booksFileSize.rawValue),
          let value = metric.measurements.first?.value
        {
          return ("fileSize", value)
        }
        return ("fileSize", nil)
      }
      group.addTask {
        if let metric = try? await ManagementService.getMetric(MetricName.books.rawValue),
          let value = metric.measurements.first?.value
        {
          return ("books", value)
        }
        return ("books", nil)
      }
      group.addTask {
        if let metric = try? await ManagementService.getMetric(MetricName.series.rawValue),
          let value = metric.measurements.first?.value
        {
          return ("series", value)
        }
        return ("series", nil)
      }
      group.addTask {
        if let metric = try? await ManagementService.getMetric(MetricName.sidecars.rawValue),
          let value = metric.measurements.first?.value
        {
          return ("sidecars", value)
        }
        return ("sidecars", nil)
      }
      group.addTask {
        if let metric = try? await ManagementService.getMetric(MetricName.collections.rawValue),
          let value = metric.measurements.first?.value
        {
          return ("collections", value)
        }
        return ("collections", nil)
      }
      group.addTask {
        if let metric = try? await ManagementService.getMetric(MetricName.readlists.rawValue),
          let value = metric.measurements.first?.value
        {
          return ("readlists", value)
        }
        return ("readlists", nil)
      }

      for await (key, value) in group {
        switch key {
        case "fileSize":
          metrics.fileSize = value
        case "books":
          metrics.booksCount = value
        case "series":
          metrics.seriesCount = value
        case "sidecars":
          metrics.sidecarsCount = value
        case "collections":
          metrics.collectionsCount = value
        case "readlists":
          metrics.readlistsCount = value
        default:
          break
        }
      }
    }

    // A failed load must not wipe the values already stored.
    guard metrics.hasAnyValue else { return }

    let database = try? await DatabaseOperator.database()
    try? await database?.upsertAllLibrariesEntry(
      instanceId: instanceId,
      fileSize: metrics.fileSize,
      booksCount: metrics.booksCount,
      seriesCount: metrics.seriesCount,
      sidecarsCount: metrics.sidecarsCount,
      collectionsCount: metrics.collectionsCount,
      readlistsCount: metrics.readlistsCount
    )
  }
}

nonisolated struct LibraryMetricValues: Equatable, Sendable {
  var fileSize: Double?
  var seriesCount: Double?
  var booksCount: Double?
  var sidecarsCount: Double?
}

private struct AllLibrariesMetricsData {
  var fileSize: Double?
  var seriesCount: Double?
  var booksCount: Double?
  var sidecarsCount: Double?
  var collectionsCount: Double?
  var readlistsCount: Double?

  var hasAnyValue: Bool {
    fileSize != nil || seriesCount != nil || booksCount != nil || sidecarsCount != nil
      || collectionsCount != nil || readlistsCount != nil
  }
}
