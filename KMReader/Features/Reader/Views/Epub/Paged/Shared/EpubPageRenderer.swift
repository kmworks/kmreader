#if os(iOS)
  import UIKit

  @MainActor
  protocol EpubPageRenderer: AnyObject {
    var contentView: UIView { get }
    var isContentLoaded: Bool { get }
    var refreshesWhenAppearingWithSameGeometry: Bool { get }
    var reloadsOnAppearanceChange: Bool { get }
    var forcesReloadWhenEnsured: Bool { get }

    func install(in container: UIView)
    func configure(_ configuration: EpubChapterConfiguration)
    func applyTheme(_ theme: ReaderTheme)
    func loadIfNeeded(force: Bool)
    func applyPagination(scrollToPage pageIndex: Int)
    func scrollToPage(_ pageIndex: Int, completion: (() -> Void)?)
    func scrollToPageAndSettle(_ pageIndex: Int, completion: @escaping () -> Void)
    func handleLinkTap(at point: CGPoint, in hostView: UIView) -> Bool
    func prepareForSnapshot()
  }
#endif
