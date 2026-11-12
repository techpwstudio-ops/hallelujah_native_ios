import SwiftUI

/// The "Video Quality" picker, the sibling of `AudioQualitySheet` and laid out the same way. It lists
/// the five preferences; which of them a given episode can actually play is the player menu's job.
struct VideoQualitySheet: View {
    struct Option: Identifiable {
        let id: VideoQuality
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let badge: String?
    }

    let selected: VideoQuality
    let onSelect: (VideoQuality) -> Void

    private let options: [Option] = [
        Option(id: .auto, title: "Auto", subtitle: "Adjusts to your connection", badge: nil),
        Option(id: .p480, title: "480p", subtitle: "Low data usage", badge: "~1.2 Mbps"),
        Option(id: .p720, title: "720p HD", subtitle: "Sharp and balanced", badge: "~2.5 Mbps"),
        Option(id: .p1080, title: "1080p Full HD", subtitle: "Sharpest streamed picture", badge: "~5 Mbps"),
        Option(id: .original, title: "Original", subtitle: "As uploaded, uses the most data", badge: nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ParityDragHandler()
            Spacer().frame(height: 16)
            Text("Video Quality")
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
                        if let badge = option.badge {
                            Text(verbatim: badge)
                                .font(AccountParity.font(11))
                                .foregroundStyle(AccountParity.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AccountParity.white12))
                        }
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
