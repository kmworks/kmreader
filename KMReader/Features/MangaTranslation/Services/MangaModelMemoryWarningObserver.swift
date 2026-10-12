#if os(iOS) || os(tvOS)
  import Foundation

  @MainActor
  final class MangaModelMemoryWarningObserver: MemoryWarningListener {
    static let shared = MangaModelMemoryWarningObserver()

    private init() {
      MemoryWarningCenter.shared.addListener(self)
    }

    func handleMemoryWarning() {
      Task {
        await MangaTranslationService.shared.releaseModels()
      }
    }
  }
#endif
