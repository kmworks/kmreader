#if os(iOS)
  import UIKit

  @MainActor
  final class CoreTextErrorPageViewController: UIViewController {
    private let message: String
    private let theme: ReaderTheme

    init(message: String, theme: ReaderTheme) {
      self.message = message
      self.theme = theme
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
      view = CoreTextChapterErrorView(message: message, theme: theme)
    }
  }
#endif
