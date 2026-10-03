import CoreGraphics
import Foundation

actor PageTranslationPipeline {
  static let shared = PageTranslationPipeline()

  private let logger = AppLogger(.reader)

  func translatedCGImage(from source: CGImage, config: PageTranslationConfig) async -> CGImage? {
    guard #available(iOS 18.0, macOS 15.0, tvOS 18.0, *), config.isUsable else { return nil }
    guard !Task.isCancelled else { return nil }

    let lines = await PageOCRService.recognizeLines(in: source)
    guard !lines.isEmpty, !Task.isCancelled else { return nil }

    let pageSize = CGSize(width: source.width, height: source.height)
    let drafts = BubbleRegionEstimator.groupIntoBubbles(lines, pageSize: pageSize)
    guard !drafts.isEmpty, let pageGrid = BubbleRegionEstimator.makePageGrid(for: source) else {
      return nil
    }

    var estimatedBubbles: [BubbleRegionEstimator.EstimatedBubble] = []
    var sourceTexts: [String] = []
    for draft in drafts {
      let sourceText = draft.lines.map(\.text).joined(separator: "\n")
      switch BubbleRegionEstimator.estimateRegion(for: draft, in: source, grid: pageGrid) {
      case .bubble(let estimated):
        estimatedBubbles.append(estimated)
        sourceTexts.append(sourceText)
      case .skipped(let reason):
        logger.debug(
          "⏭️ [Translate] Skip bubble \"\(sourceText.replacingOccurrences(of: "\n", with: " "))\": \(reason)"
        )
      }
    }
    guard !estimatedBubbles.isEmpty else {
      logger.debug("⏭️ [Translate] No translatable bubbles on page")
      return nil
    }
    guard !Task.isCancelled else { return nil }

    let service = PageTranslationLLMService(config: config)
    let translations: [String]
    do {
      translations = try await service.translate(sourceTexts)
    } catch {
      logger.error("❌ [Translate] LLM translation failed: \(error)")
      return nil
    }
    guard !Task.isCancelled else { return nil }

    let bubbles = zip(zip(estimatedBubbles, sourceTexts), translations).map { pair, translated in
      TranslatedBubble(
        regionRect: pair.0.regionRect,
        maskImage: pair.0.maskImage,
        backgroundColor: pair.0.backgroundColor,
        sourceText: pair.1,
        translatedText: translated
      )
    }

    guard let rendered = TranslatedPageRenderer.render(source: source, bubbles: bubbles) else {
      logger.error("❌ [Translate] Failed to render translated page")
      return nil
    }
    return rendered
  }
}
