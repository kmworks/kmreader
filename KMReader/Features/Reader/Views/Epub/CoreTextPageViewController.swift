#if os(iOS)
  import UIKit
  import YueduCoreText

  @MainActor
  final class CoreTextPageViewController: UIViewController {
    let pageIndex: Int
    let linkRegions: LinkInteractionRegionSet

    private let displayList: DisplayList
    private let theme: ReaderTheme

    init(pageIndex: Int, displayList: DisplayList, linkRegions: LinkInteractionRegionSet, theme: ReaderTheme) {
      self.pageIndex = pageIndex
      self.displayList = displayList
      self.linkRegions = linkRegions
      self.theme = theme
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
      let contentView = CoreTextDisplayListView()
      contentView.backgroundColor = theme.uiColorBackground
      contentView.displayList = displayList
      view = contentView
    }
  }
#endif
