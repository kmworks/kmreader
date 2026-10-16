#if os(iOS) || os(macOS)
  enum PdfLoadingStage: String {
    case idle
    case fetchingMetadata
    case downloading
    case finalizingOfflineDownload
    case preparingReader
  }
#endif
