#if os(iOS) || os(macOS)
  import SwiftUI

  /// Floating preview of a footnote reference, docked to the bottom of the reading area.
  ///
  /// It is presented by the reader shell rather than by a page controller, because the
  /// paged engines clip their page content and the scrolled engines have no tap point.
  @MainActor
  struct EpubFootnotePopupView: View {
    let footnote: EpubFootnote
    let theme: ReaderTheme
    let onOpenLink: (URL) -> Void
    let onOpenFullNote: () -> Void
    let onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 0

    private let maximumWidth: CGFloat = 460
    private let horizontalInset: CGFloat = 16
    /// Height estimates for the chrome around the note body, used only to cap
    /// the body so the card cannot grow past half the reading area.
    private let estimatedHeaderHeight: CGFloat = 40
    private let estimatedFooterHeight: CGFloat = 44

    var body: some View {
      #if os(macOS)
        popup
          .onExitCommand(perform: onDismiss)
      #else
        popup
      #endif
    }

    private var popup: some View {
      GeometryReader { geometry in
        let width = min(max(geometry.size.width - horizontalInset * 2, 0), maximumWidth)
        let maximumHeight = min(max(geometry.size.height * 0.5, 160), 420)

        ZStack(alignment: .bottom) {
          Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)

          card(width: width, maximumHeight: maximumHeight)
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, 24)
        }
      }
      .accessibilityAddTraits(.isModal)
      .accessibilityAction(.escape, onDismiss)
      .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func card(width: CGFloat, maximumHeight: CGFloat) -> some View {
      let reservedHeight = estimatedHeaderHeight + (footnote.truncated ? estimatedFooterHeight : 0)
      let bodyHeight = min(max(contentHeight, 44), max(44, maximumHeight - reservedHeight))

      return VStack(alignment: .leading, spacing: 0) {
        header
        EpubFootnoteBodyView(
          footnote: footnote,
          theme: theme,
          onContentHeightChange: { height in
            contentHeight = height
          },
          onOpenLink: onOpenLink
        )
        .frame(height: bodyHeight)
        if footnote.truncated {
          footer
        }
      }
      .frame(width: width, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(theme.backgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(theme.textColor.opacity(0.12), lineWidth: 1)
      )
      .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.18), radius: 18, x: 0, y: 8)
      .accessibilityElement(children: .contain)
    }

    private var header: some View {
      HStack(spacing: 8) {
        Text("Footnote")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(theme.textColor.opacity(0.6))

        Spacer(minLength: 0)

        Button(action: onDismiss) {
          Image(systemName: AppIcon.close)
            .imageScale(.small)
            .foregroundStyle(theme.textColor.opacity(0.6))
            .contentShape(Rectangle())
        }
        .adaptiveButtonStyle(.plain)
        .accessibilityLabel(Text("Close"))
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 8)
    }

    private var footer: some View {
      VStack(spacing: 0) {
        Divider()
          .overlay { theme.textColor.opacity(0.08) }
        Button(action: onOpenFullNote) {
          Text("Open Full Note")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(accentColor)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .adaptiveButtonStyle(.plain)
        .padding(.vertical, 13)
      }
    }

    private var accentColor: Color {
      Color(hex: theme.isDark ? "#4CA6FF" : "#0066CC") ?? theme.textColor
    }
  }
#endif
