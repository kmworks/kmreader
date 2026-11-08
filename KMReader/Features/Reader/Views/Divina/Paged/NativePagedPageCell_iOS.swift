#if os(iOS) || os(tvOS)
  import SwiftUI
  import UIKit

  final class NativePagedPageCell: UICollectionViewCell {
    private let pagedContentView = NativePagedPageContentView()

    override init(frame: CGRect) {
      super.init(frame: frame)
      contentView.addSubview(pagedContentView)
      pagedContentView.translatesAutoresizingMaskIntoConstraints = false

      NSLayoutConstraint.activate([
        pagedContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        pagedContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        pagedContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
        pagedContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      ])
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func configure(
      viewModel: ReaderViewModel,
      item: ReaderViewItem,
      wholeSpread: WholeSpreadPresentation?,
      screenSize: CGSize,
      renderConfig: ReaderRenderConfig,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      isPlaybackActive: Bool
    ) {
      pagedContentView.configure(
        viewModel: viewModel,
        item: item,
        wholeSpread: wholeSpread,
        screenSize: screenSize,
        renderConfig: renderConfig,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode,
        isPlaybackActive: isPlaybackActive,
        tracksGlobalZoomState: true
      )
    }

    func updatePlaybackActive(_ isPlaybackActive: Bool) {
      pagedContentView.updatePlaybackActive(isPlaybackActive)
    }

    func panWholeSpread(to edge: ReaderSpreadEdge, animated: Bool) {
      pagedContentView.panWholeSpread(to: edge, animated: animated)
    }

    func canPanWholeSpread(forHorizontalDrag translationX: CGFloat) -> Bool {
      pagedContentView.canPanWholeSpread(forHorizontalDrag: translationX)
    }

    func resetContent(backgroundColor: UIColor) {
      self.backgroundColor = backgroundColor
      contentView.backgroundColor = backgroundColor
      pagedContentView.resetContent(backgroundColor: backgroundColor)
    }

    override func prepareForReuse() {
      super.prepareForReuse()
      pagedContentView.resetContent()
    }
  }
#endif
