import SwiftUI

/// Flutter-parity constants and small shared views for the account area
/// (settings, profile, subscription, support, tips, deletion, share). Values
/// are lifted from `lib/theme/colors.dart` (`ColorTheme`) and the Material 3
/// defaults the Flutter theme leaves untouched. Kept inside the Settings
/// feature so no shared token file is edited (D12).
enum AccountParity {
    // MARK: Colours (ColorTheme)
    static let black = Color.black
    static let white = Color.white
    static let white70 = Color.white.opacity(0.7)
    static let white60 = Color.white.opacity(0.6)
    static let white54 = Color.white.opacity(0.54)
    static let white24 = Color.white.opacity(0.24)
    static let white12 = Color.white.opacity(0.12)
    static let white10 = Color.white.opacity(0.10)
    static let tertiaryText = Color.white.opacity(0.47)
    /// `ColorTheme.borderColor` = Colors.grey @ 0.2
    static let border = Color(red: 0.62, green: 0.62, blue: 0.62).opacity(0.2)
    /// `Colors.grey` (0xFF9E9E9E)
    static let grey = Color(red: 0.62, green: 0.62, blue: 0.62)
    static let fill = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1D / 255)
    static let sheetBackground = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let darkFill = Color(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    static let gold = Color(red: 1.0, green: 0xC8 / 255, blue: 0x57 / 255)
    static let red = Color(red: 0xBA / 255, green: 0x03 / 255, blue: 0x19 / 255)
    static let errorBg = Color(red: 0x7F / 255, green: 0, blue: 0)
    static let dragHandle = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
    static let greenAccent = Color.green

    // MARK: Fonts (Material 3 text theme with AppTextStyles overrides)
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(Typography.fontFamily, size: size).weight(weight)
    }
    /// Material default `headlineSmall` (24 / w400), not overridden by AppTextStyles.
    static let headlineSmall = font(24, .regular)
    static let titleLarge = font(20, .semibold)
    static let titleMedium = font(16, .semibold)
    static let titleSmall = font(14, .semibold)
    static let bodyLarge = font(16)
    static let bodyMedium = font(14)
    static let bodySmall = font(12)
}

/// AppBar title on a black scaffold. Material centres it on iOS unless
/// `centerTitle: false` is passed (Settings only), so `leading` defaults to
/// false. `titleLarge` 20/w600 (`appBarTextStyle`).
private struct ParityNavTitle<TitleContent: View>: ViewModifier {
    let leading: Bool
    let titleContent: TitleContent
    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Flutter AppBar is solid black with no scrolled-under tint.
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: leading ? .topBarLeading : .principal) {
                    titleContent
                }
            }
    }
}

extension View {
    /// Flutter `AppBar(title: Text(title, style: appBarTextStyle))`.
    func parityNavTitle(_ title: String, leading: Bool = false) -> some View {
        modifier(ParityNavTitle(
            leading: leading,
            titleContent: Text(title)
                .font(AccountParity.titleLarge)
                .foregroundStyle(AccountParity.white)
        ))
    }

    /// AppBar with a custom title widget.
    func parityNavTitle<TitleContent: View>(leading: Bool = false, @ViewBuilder content: () -> TitleContent) -> some View {
        modifier(ParityNavTitle(leading: leading, titleContent: content()))
    }

    /// Black scaffold background filling the safe area.
    func parityScaffold() -> some View {
        background(AccountParity.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}

/// `CustomHeading`: titleSmall in white70.
struct ParityHeading: View {
    let text: String
    var body: some View {
        HStack {
            Text(text)
                .font(AccountParity.titleSmall)
                .foregroundStyle(AccountParity.white70)
            Spacer(minLength: 0)
        }
    }
}

/// `SettingsListItem`: Material two-line `ListTile` with zero content padding,
/// a 1pt `borderColor` bottom rule, 17/w600 title, grey subtitle.
struct ParityListTile<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let row = HStack(spacing: 0) {
            leading()
                .frame(minWidth: 40, alignment: .leading)
            Spacer().frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AccountParity.font(17, .semibold))
                    .foregroundStyle(AccountParity.white)
                if let subtitle {
                    Text(subtitle)
                        .font(AccountParity.bodyMedium)
                        .foregroundStyle(AccountParity.grey)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: subtitle == nil ? 56 : 72)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AccountParity.border).frame(height: 1)
        }
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { row }.buttonStyle(ParityRowPressStyle())
        } else {
            row
        }
    }
}

/// Material ink-splash stand-in for tappable list rows: a faint white wash while pressed.
struct ParityRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// `SettingsArrowNextIcon` stand-in (asset `settings_arrow_next.svg` not yet in the catalog).
struct ParityArrowNext: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AccountParity.white)
    }
}

/// White-on-black `FilledButton` with Material M3 metrics (min height 40, 24pt
/// horizontal padding, 8pt radius, `titleMedium` label in black).
struct ParityFilledButton: View {
    let title: String
    var fillWidth: Bool = false
    var isLoading: Bool = false
    var enabled: Bool = true
    var background: Color = AccountParity.white
    var foreground: Color = AccountParity.black
    var height: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    Text(title).font(AccountParity.titleMedium).foregroundStyle(foreground)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                    .fill(enabled ? background : background.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
    }
}

/// `DragHandler` (`lib/widgets/drag_handler.dart`): 80x2, 2pt radius, `dragHandlerColor`.
struct ParityDragHandler: View {
    var margin: CGFloat = 16
    var width: CGFloat? = nil
    var color: Color = AccountParity.dragHandle

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: width ?? Dimens.dragHandlerWidth, height: Dimens.dragHandlerHeight)
            Spacer(minLength: 0)
        }
        .padding(.vertical, margin)
    }
}

/// Dialog body replicating `showConfirmationDialog` (`lib/dialogs/confirmation_dialog.dart`).
struct ParityConfirmationDialog: View {
    var title: String = "Confirm"
    var message: String?
    var systemIcon: String = "questionmark.circle"
    var force: Bool = false
    var confirmTitle: String? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { if !force { onCancel() } }
            VStack(spacing: 0) {
                Spacer().frame(height: 22)
                ZStack {
                    Circle().fill(Color.white.opacity(0.06))
                    Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    Image(systemName: systemIcon)
                        .font(.system(size: 34))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 64, height: 64)
                Spacer().frame(height: 18)
                Text(title)
                    .font(AccountParity.font(22, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 10)
                if let message {
                    Text(message)
                        .font(AccountParity.font(15))
                        .lineSpacing(15 * 0.45)
                        .tracking(-0.1)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Spacer().frame(height: 22)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                HStack(spacing: 0) {
                    if !force {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(AccountParity.font(17, .medium))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                    }
                    Button(action: onConfirm) {
                        Text(confirmTitle ?? (force ? "Continue" : "Yes"))
                            .font(AccountParity.font(17, .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 58)
            }
            .frame(maxWidth: 420)
            .glassRounded(28)
            .shadow(color: Color.black.opacity(0.45), radius: 30, x: 0, y: 16)
            .padding(.horizontal, 22)
            .scaleEffect(shown ? 1 : 0.95)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) { shown = true }
        }
    }
}

private struct ParityConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String?
    let systemIcon: String
    let force: Bool
    let confirmTitle: String?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            ParityConfirmationDialog(
                title: title,
                message: message,
                systemIcon: systemIcon,
                force: force,
                confirmTitle: confirmTitle,
                onCancel: { isPresented = false },
                onConfirm: {
                    isPresented = false
                    onConfirm()
                }
            )
            .presentationBackground(.clear)
        }
    }
}

extension View {
    /// Flutter `showConfirmationDialog` equivalent (blurred-dark rounded card, Cancel / Yes).
    func parityConfirmationDialog(
        isPresented: Binding<Bool>,
        title: String = "Confirm",
        message: String?,
        systemIcon: String = "questionmark.circle",
        force: Bool = false,
        confirmTitle: String? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(ParityConfirmationModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            systemIcon: systemIcon,
            force: force,
            confirmTitle: confirmTitle,
            onConfirm: onConfirm
        ))
    }
}

/// `textInput` / `buildInputDecoration` field: filled `ColorTheme.fillColor`,
/// 8pt radius, 12/16 content padding, 12pt w500 grey hint, 16pt value text.
struct ParityTextField: View {
    @Binding var text: String
    var placeholder: String
    var enabled: Bool = true
    var errorMessage: String? = nil
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .never
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int> = 1...1
    var characterLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(AccountParity.font(12, .medium))
                        .foregroundStyle(Color(red: 0x80 / 255, green: 0x80 / 255, blue: 0x80 / 255))
                        .padding(.top, axis == .vertical ? 2 : 0)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text, axis: axis)
                    .lineLimit(lineLimit)
                    .font(AccountParity.bodyLarge)
                    .foregroundStyle(enabled ? AccountParity.white : Color.white.opacity(0.38))
                    .tint(Color.yellow)
                    .keyboardType(keyboard)
                    .textContentType(contentType)
                    .textInputAutocapitalization(capitalization)
                    .disabled(!enabled)
                    .onChange(of: text) { _, newValue in
                        if let characterLimit, newValue.count > characterLimit {
                            text = String(newValue.prefix(characterLimit))
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadius, style: .continuous)
                    .fill(AccountParity.fill)
            )
            if let errorMessage {
                Text(errorMessage)
                    .font(AccountParity.bodySmall)
                    .foregroundStyle(AccountParity.red)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
            }
        }
    }
}

/// `Text.rich("Label" + red " * ")` field label (`titleSmall`).
struct ParityRequiredLabel: View {
    let text: String
    var required: Bool = true
    var body: some View {
        (Text(text).font(AccountParity.titleSmall).foregroundStyle(AccountParity.white)
            + Text(required ? " * " : "").font(AccountParity.titleSmall).foregroundStyle(Color.red))
    }
}

// MARK: - Bottom-sheet primitives (`showAppSheet`)

private struct ParityHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Sizes the sheet to its content (Flutter `showModalBottomSheet` +
/// `Column(mainAxisSize: min)`), on the flat `bottomSheetBgColor` fill.
private struct ParityFitSheetContent<Content: View>: View {
    let cornerRadius: CGFloat
    let dismissible: Bool
    let content: Content
    @State private var height: CGFloat = 320

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ParityHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(ParityHeightKey.self) { newValue in
                if newValue > 0 { height = newValue }
            }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(AccountParity.sheetBackground)
            .presentationCornerRadius(cornerRadius)
            .interactiveDismissDisabled(!dismissible)
    }
}

extension View {
    /// Presents `content` as a content-height bottom sheet with Flutter's
    /// sheet chrome (flat #111111, no system drag indicator; add
    /// `ParityDragHandler` inside the content as Flutter does).
    func parityFitSheet<Content: View>(
        isPresented: Binding<Bool>,
        cornerRadius: CGFloat = 28,
        dismissible: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            ParityFitSheetContent(cornerRadius: cornerRadius, dismissible: dismissible, content: content())
        }
    }

    func parityFitSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        cornerRadius: CGFloat = 28,
        dismissible: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            ParityFitSheetContent(cornerRadius: cornerRadius, dismissible: dismissible, content: content(value))
        }
    }
}

/// `Bullet` (`lib/widgets/widgets.dart`): 6pt white70 dot, 10pt gap, bodyMedium
/// white70 at height 1.4, 10pt bottom padding.
struct ParityBullet: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(AccountParity.white70)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(AccountParity.bodyMedium)
                .lineSpacing(14 * 0.4 - 3)
                .foregroundStyle(AccountParity.white70)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 10)
    }
}

/// Sheet buttons: Material `FilledButton` (white/black by default theme) and
/// `OutlinedButton` with configurable radius, vertical padding and border.
struct ParitySheetButton: View {
    enum Style { case filled, outlined }

    let title: String
    var style: Style = .filled
    var radius: CGFloat = 14
    var verticalPadding: CGFloat = 16
    var borderColor: Color = Color(white: 0.74)
    var fillColor: Color = AccountParity.white
    var foreground: Color? = nil
    var weight: Font.Weight = .semibold
    var isLoading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(style == .filled ? AccountParity.black : AccountParity.white)
                } else {
                    Text(title)
                        .font(AccountParity.font(14, weight))
                        .tracking(0.1)
                        .foregroundStyle(foreground ?? (style == .filled ? AccountParity.black : AccountParity.white))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .modifier(ParitySheetButtonSurface(
                outlined: style == .outlined, radius: radius, fillColor: fillColor
            ))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Flutter's `AlertIcon` / `TickIcon` SVG stand-ins (assets
/// `cancel_premium_icon.svg`, `tick-circle.svg` not yet in the catalog).
struct ParitySheetIcon: View {
    enum Kind { case alert, tick, system(String) }
    let kind: Kind
    var size: CGFloat = 56

    var body: some View {
        switch kind {
        case .alert:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: size * 0.7))
                .foregroundStyle(AccountParity.white)
                .frame(width: size, height: size)
        case .tick:
            Image(systemName: "checkmark.circle")
                .font(.system(size: size * 0.8))
                .foregroundStyle(AccountParity.white)
                .frame(width: size, height: size)
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.8))
                .foregroundStyle(AccountParity.white)
                .frame(width: size, height: size)
        }
    }
}

/// Filled keeps Flutter's solid fill; outlined becomes interactive glass.
private struct ParitySheetButtonSurface: ViewModifier {
    let outlined: Bool
    let radius: CGFloat
    let fillColor: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if outlined {
            content.glassRounded(radius, interactive: true)
        } else {
            content.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fillColor)
            )
        }
    }
}
