#if os(iOS) || os(macOS)
  enum LoadingStage: String {
    case idle
    case fetchingMetadata
    case downloading
    case finalizingOfflineDownload
    case preparingOfflineResources
    case preparingReader
    case paginating
  }
#endif
