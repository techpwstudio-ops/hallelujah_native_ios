import SwiftUI

/// Grab affordance for a custom sheet. Built even though Flutter explicitly
/// disables its own (`showAppSheet` in `lib/sheets/app_sheet.dart` sets
/// `showDragHandle: false` and draws none of its own) — T12 calls for a
/// drag-handle component directly, and it is the iOS convention every native
/// sheet in this app will be compared against.
struct SheetDragHandle: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Capsule(style: .continuous)
            .fill(theme.color(.border))
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.sm)
    }
}

/// Standard chrome for custom sheet content: a top-rounded `GlassSurface`
/// (`GlassSurface`'s own doc comment already lists "sheets" among the raised
/// surfaces the glass system covers) with a drag handle — replacing Dart's
/// flat `ColorTheme.bottomSheetBgColor` fill (`lib/sheets/app_sheet.dart`).
/// Sheets sit outside D10's pixel-parity scope, so upgrading the fill to
/// glass here is exactly the improvement building the glass system was for.
struct AppSheetContainer<Content: View>: View {
    private let showsDragHandle: Bool
    private let content: Content

    /// Optional, not required: sheets aren't guaranteed to be presented from
    /// inside `AppShellView`'s subtree (e.g. during the pre-sign-in flow), so
    /// this reads as `nil` rather than crashing when no coordinator is in the
    /// environment. See `AppNavigationCoordinator.openSheetCount` (T17) —
    /// mirrors `ios26OpenSheetCount` (`lib/widgets/navigation/
    /// our_adaptive_scaffold.dart`), incremented/decremented here rather than
    /// at every `.appSheet()` call site since they all funnel through this
    /// one container.
    @Environment(AppNavigationCoordinator.self) private var coordinator: AppNavigationCoordinator?

    init(showsDragHandle: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsDragHandle = showsDragHandle
        self.content = content()
    }

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Radius.xl,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Radius.xl,
            style: .continuous
        )
    }

    var body: some View {
        GlassSurface(.regular, in: sheetShape) {
            VStack(spacing: 0) {
                if showsDragHandle {
                    SheetDragHandle()
                }
                content
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { coordinator?.sheetPresented() }
        .onDisappear { coordinator?.sheetDismissed() }
    }
}

extension View {
    /// Presents `content` with the app's standard sheet chrome (glass
    /// background, own drag handle) — mirrors `showAppSheet`'s always
    /// `isScrollControlled: true`, drag-to-dismiss behavior via
    /// `presentationDetents`/`interactiveDismissDisabled(false)` (the
    /// default).
    func appSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented) {
            AppSheetContainer(content: content)
                .presentationDetents(detents)
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
    }
}
