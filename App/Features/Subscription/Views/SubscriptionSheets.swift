import SwiftUI

/// Ports `lib/sheets/subscription/*`. Every sheet is a content view meant to
/// be presented with `.parityFitSheet` (flat #111111 chrome, content-height
/// detent). Layout constants are lifted from the Dart widget trees; the
/// SVG icons (`AlertIcon`, `TickIcon`) are SF Symbol stand-ins.

enum SubscriptionSheetFormat {
    /// `Formater.formatToDate`: dd/MM/yyyy (local).
    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    /// `premiumEndingSoonSheet._formatDate`: "5 Mar 2026".
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

private func sheetTitle(_ text: String, weight: Font.Weight = .bold) -> some View {
    Text(text)
        .font(AccountParity.font(24, weight))
        .foregroundStyle(AccountParity.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
}

// MARK: - Confirm / alert sheets with two buttons in a row

/// `showRemoveMemberSheet` / `showCancelInviteConfirmationSheet`: alert icon,
/// title, white70 body, outlined + white buttons side by side (12pt radius).
struct ParityConfirmSheet: View {
    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 16)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            sheetTitle(title)
            Spacer().frame(height: 8)
            Text(message)
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 28)
            HStack(spacing: 12) {
                ParitySheetButton(
                    title: cancelTitle, style: .outlined, radius: 12, verticalPadding: 14,
                    borderColor: AccountParity.white24, action: onCancel
                )
                ParitySheetButton(
                    title: confirmTitle, style: .filled, radius: 12, verticalPadding: 14, action: onConfirm
                )
            }
            Spacer().frame(height: 8)
        }
        .padding(.horizontal, Dimens.paddingLarge)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }
}

// MARK: - Invite member

/// `showInviteMemberSheet`: not dismissible by drag/tap-outside.
struct InviteMemberSheet: View {
    let isSending: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSend: (String) -> Void

    @State private var identifier = ""

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 16)
            sheetTitle("Invite a Family Member")
            Spacer().frame(height: 10)
            Text("Enter an email address or phone number. We\u{2019}ll send them a link to join your Family Plan.")
                .font(AccountParity.bodyMedium)
                .lineSpacing(14 * 0.4 - 3)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 20)
            Text("Email or Phone Number")
                .font(AccountParity.font(14, .semibold))
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 8)
            ZStack(alignment: .leading) {
                if identifier.isEmpty {
                    Text("Email or Phone Number")
                        .font(AccountParity.bodyLarge)
                        .foregroundStyle(Color(red: 0.62, green: 0.62, blue: 0.62))
                        .allowsHitTesting(false)
                }
                TextField("", text: $identifier)
                    .font(AccountParity.bodyLarge)
                    .foregroundStyle(AccountParity.white)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AccountParity.black)
            )
            if let errorMessage {
                Text(errorMessage)
                    .font(AccountParity.bodySmall)
                    .foregroundStyle(AccountParity.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            Spacer().frame(height: 10)
            Text("They must have a Hallelujah account to join.")
                .font(AccountParity.bodySmall)
                .foregroundStyle(AccountParity.white54)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 24)
            HStack(spacing: 12) {
                ParitySheetButton(
                    title: "Cancel", style: .outlined, radius: 12, verticalPadding: 14,
                    borderColor: AccountParity.white24, action: onCancel
                )
                ParitySheetButton(
                    title: "Send Invite", style: .filled, radius: 12, verticalPadding: 14, isLoading: isSending
                ) {
                    let value = identifier.trimmingCharacters(in: .whitespaces)
                    if value.isEmpty { return }
                    onSend(value)
                }
            }
            Spacer().frame(height: 12)
            Text("Each invite expires in 48 hours.")
                .font(AccountParity.bodySmall)
                .foregroundStyle(Color.white.opacity(0.38))
            Spacer().frame(height: 8)
        }
        .padding(.horizontal, Dimens.paddingLarge)
        .padding(.top, 20)
    }
}

/// `showInviteSentSheet`: auto-closes after 3 seconds.
struct InviteSentSheet: View {
    let identifier: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 16)
            ParitySheetIcon(kind: .tick)
            Spacer().frame(height: 12)
            Text("Invite sent to \(identifier)")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 6)
            Text("Each invite expires in 48 hours")
                .font(AccountParity.bodySmall)
                .foregroundStyle(Color.white.opacity(0.38))
                .multilineTextAlignment(.center)
            Spacer().frame(height: 48)
        }
        .frame(maxWidth: .infinity)
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            onClose()
        }
    }
}

// MARK: - Premium lifecycle sheets (stacked full-width buttons)

private struct StackedSheet<Inner: View>: View {
    let body_: Inner
    init(@ViewBuilder _ body: () -> Inner) { body_ = body() }
    var body: some View {
        VStack(spacing: 0) {
            body_
        }
        .padding(.horizontal, Dimens.paddingLarge)
        .padding(.vertical, 20)
    }
}

/// `showRenewPlanSheet`.
struct RenewPlanSheet: View {
    let endDate: Date
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        StackedSheet {
            ParityDragHandler()
            Spacer().frame(height: 12)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            sheetTitle("Renew Premium?")
            Spacer().frame(height: 16)
            ParityBullet(text: "Your Premium will be extended immediately after renewal")
            ParityBullet(text: "Next billing date: \(SubscriptionSheetFormat.date(endDate))")
            Spacer().frame(height: 28)
            ParitySheetButton(title: "Confirm & Renew", action: onConfirm)
            Spacer().frame(height: 12)
            ParitySheetButton(title: "Not Now", style: .outlined, action: onDismiss)
            Spacer().frame(height: 8)
        }
    }
}

/// `showCancelPlanSheet`.
struct CancelPlanSheet: View {
    let endDate: Date
    let onKeep: () -> Void
    let onCancelSubscription: () -> Void

    var body: some View {
        StackedSheet {
            ParityDragHandler()
            Spacer().frame(height: 12)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            sheetTitle("Cancel Premium?")
            Spacer().frame(height: 16)
            ParityBullet(text: "All members will keep Premium access until \(SubscriptionSheetFormat.date(endDate))")
            ParityBullet(text: "After that, everyone will switch to the Free plan")
            ParityBullet(text: "You can restart Premium anytime")
            Spacer().frame(height: 28)
            ParitySheetButton(title: "Keep Premium", action: onKeep)
            Spacer().frame(height: 12)
            ParitySheetButton(title: "Cancel Subscription", style: .outlined, action: onCancelSubscription)
            Spacer().frame(height: 8)
        }
    }
}

/// `showConfirmCancelSheet` (confirm_subscription.dart): left-aligned body.
struct ConfirmCancelSheet: View {
    let endDate: Date
    let onKeep: () -> Void
    let onCancelSubscription: () -> Void

    var body: some View {
        StackedSheet {
            ParityDragHandler()
            Spacer().frame(height: 16)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            Text("Confirm Cancellation")
                .font(AccountParity.headlineSmall)
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 16)
            Text("Your Premium plan will remain active until \(SubscriptionSheetFormat.date(endDate)).")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 16)
            Text("After this date:")
                .font(AccountParity.titleMedium)
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 12)
            plainBullet("Ads will return")
            plainBullet("Audio quality will switch to standard")
            plainBullet("Downloads will be disabled")
            Spacer().frame(height: 28)
            ParitySheetButton(title: "Keep Premium", radius: 8, verticalPadding: 10, weight: .semibold, action: onKeep)
            Spacer().frame(height: 12)
            ParitySheetButton(
                title: "Cancel Subscription", style: .outlined, radius: 8, verticalPadding: 10,
                borderColor: AccountParity.white, weight: .medium, action: onCancelSubscription
            )
            Spacer().frame(height: 8)
        }
    }

    private func plainBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(AccountParity.white).frame(width: 6, height: 6).padding(.top, 6)
            Text(text)
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 10)
    }
}

/// `showCancelledSheet` result sheet ("Subscription Cancelled").
struct SubscriptionCancelledSheet: View {
    let endDate: Date
    let onContinueListening: () -> Void
    let onReactivate: () -> Void

    var body: some View {
        StackedSheet {
            ParityDragHandler()
            Spacer().frame(height: 16)
            ParitySheetIcon(kind: .tick)
            Spacer().frame(height: 20)
            Text("Subscription Cancelled")
                .font(AccountParity.headlineSmall)
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 16)
            Text("Your Premium benefits will continue until \(SubscriptionSheetFormat.date(endDate)).\nYou can re-activate Premium anytime from the subscription page.")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 28)
            ParitySheetButton(title: "Continue Listening", radius: 8, verticalPadding: 10, weight: .semibold, action: onContinueListening)
            Spacer().frame(height: 12)
            ParitySheetButton(
                title: "Reactivate Premium", style: .outlined, radius: 8, verticalPadding: 10,
                borderColor: AccountParity.white, weight: .medium, action: onReactivate
            )
            Spacer().frame(height: 8)
        }
    }
}

/// `showRenewBlockedSheet`.
struct RenewBlockedSheet: View {
    let endDate: Date
    let onClose: () -> Void

    var body: some View {
        StackedSheet {
            ParityDragHandler()
            Spacer().frame(height: 12)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            sheetTitle("Already Active")
            Spacer().frame(height: 16)
            ParityBullet(text: "Your current plan is active until \(SubscriptionSheetFormat.date(endDate))")
            ParityBullet(text: "You have already cancelled auto-renew for this plan")
            ParityBullet(text: "You can renew this plan after it expires")
            Spacer().frame(height: 28)
            ParitySheetButton(title: "Got it", action: onClose)
            Spacer().frame(height: 8)
        }
    }
}

/// `showInviteReceivedSheet`.
struct InviteReceivedSheet: View {
    let inviterName: String
    let planName: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        StackedSheet {
            ParityDragHandler()
            Spacer().frame(height: 16)
            ParitySheetIcon(kind: .system("person.badge.plus"))
            Spacer().frame(height: 20)
            sheetTitle("You're Invited \u{1F389}")
            Spacer().frame(height: 14)
            Text("\(inviterName) invited you to join their \(planName).")
                .font(AccountParity.bodyMedium)
                .lineSpacing(14 * 0.4 - 3)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 16)
            ParityBullet(text: "Get access to Premium features")
            ParityBullet(text: "Share benefits with family members")
            ParityBullet(text: "You can leave anytime")
            Spacer().frame(height: 28)
            ParitySheetButton(title: "Accept Invitation", action: onAccept)
            Spacer().frame(height: 12)
            ParitySheetButton(title: "Decline", style: .outlined, action: onDecline)
            Spacer().frame(height: 8)
        }
    }
}

/// `showPremiumEndingSoonSheet` (own 24pt-radius container, black-on-white button).
struct PremiumEndingSoonSheet: View {
    let billingEndDate: Date
    let onSubscribe: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 24)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            sheetTitle("Premium access may end soon", weight: .semibold)
            Spacer().frame(height: 12)
            Text("Your Family Plan will continue until \(SubscriptionSheetFormat.shortDate(billingEndDate)).")
                .font(AccountParity.bodyMedium)
                .foregroundStyle(AccountParity.white70)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 12)
            Text("The Family Plan owner has requested account deletion.")
                .font(AccountParity.bodySmall)
                .foregroundStyle(AccountParity.white60)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 24)
            ParitySheetButton(title: "Subscribe", radius: 14, verticalPadding: 14, action: onSubscribe)
            Spacer().frame(height: 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// `showPremiumEndedSheet`.
struct PremiumEndedSheet: View {
    let ownerName: String
    let onSubscribe: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 24)
            ParitySheetIcon(kind: .alert)
            Spacer().frame(height: 20)
            sheetTitle("Your Premium access has ended", weight: .semibold)
            Spacer().frame(height: 12)
            HStack(spacing: 8) {
                ParitySheetIcon(kind: .alert)
                Text("\(ownerName) has expired.")
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white70)
            }
            Spacer().frame(height: 12)
            Text("Your music stays with you, subscribe to Premium to keep the experience ad-free.")
                .font(AccountParity.bodySmall)
                .foregroundStyle(AccountParity.white60)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 24)
            ParitySheetButton(title: "Subscribe", radius: 14, verticalPadding: 14, action: onSubscribe)
            Spacer().frame(height: 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// `showSubscribedSuccessSheet`: circle (0-0.4) -> tick easeOutBack (0.4-0.8)
/// -> fade+slide copy (0.6-1.0) over 900ms; auto-closes after 3s; not
/// dismissible.
struct SubscribedSuccessSheet: View {
    let onClose: () -> Void

    @State private var circleScale: CGFloat = 0
    @State private var tickScale: CGFloat = 0
    @State private var textVisible = false

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 20)
            ZStack {
                Circle().fill(AccountParity.white)
                    .frame(width: 72, height: 72)
                    .scaleEffect(circleScale)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AccountParity.black)
                    .scaleEffect(tickScale)
            }
            Spacer().frame(height: 24)
            VStack(spacing: 12) {
                Text("You\u{2019}re Premium!")
                    .font(AccountParity.headlineSmall)
                    .foregroundStyle(AccountParity.white)
                    .multilineTextAlignment(.center)
                Text("Welcome to Premium \u{1F389}\nEnjoy ad-free music, better quality, and downloads.")
                    .font(AccountParity.bodyMedium)
                    .foregroundStyle(AccountParity.white)
                    .multilineTextAlignment(.center)
            }
            .opacity(textVisible ? 1 : 0)
            .offset(y: textVisible ? 0 : 20)
            Spacer().frame(height: 12)
        }
        .padding(.horizontal, Dimens.paddingLarge)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.36)) { circleScale = 1 }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.6).delay(0.36)) { tickScale = 1 }
            withAnimation(.easeIn(duration: 0.36).delay(0.54)) { textVisible = true }
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            onClose()
        }
    }
}

// MARK: - Audio quality

/// `showAudioQualitySheet`.
struct AudioQualitySheet: View {
    struct Option: Identifiable {
        let id: AudioQuality
        let title: String
        let subtitle: String
        let badge: String
    }

    let selected: AudioQuality
    let onSelect: (AudioQuality) -> Void

    private let options: [Option] = [
        Option(id: .low, title: "Data Saver", subtitle: "Low data usage", badge: "24\u{2013}64 kbps"),
        Option(id: .standard, title: "Standard", subtitle: "Balanced quality", badge: "96\u{2013}160 kbps"),
        Option(id: .high, title: "High Quality", subtitle: "Clearer and richer sound", badge: "320 kbps"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 16)
            Text("Audio Quality")
                .font(AccountParity.titleLarge)
                .foregroundStyle(AccountParity.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 16)
            ForEach(options) { option in
                tile(option)
                if option.id != options.last?.id {
                    Spacer().frame(height: 12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private func tile(_ option: Option) -> some View {
        Button {
            onSelect(option.id)
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(AccountParity.font(14, .semibold))
                            .foregroundStyle(AccountParity.white)
                        Text(option.badge)
                            .font(AccountParity.font(11))
                            .foregroundStyle(AccountParity.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AccountParity.white12))
                    }
                    Spacer().frame(height: 4)
                    Text(option.subtitle)
                        .font(AccountParity.font(12))
                        .foregroundStyle(AccountParity.white54)
                }
                Spacer(minLength: 0)
                if selected == option.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AccountParity.black)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AccountParity.white))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous).fill(AccountParity.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Dimens.cornerRadiusMedium, style: .continuous)
                    .strokeBorder(selected == option.id ? AccountParity.white : Color.clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
