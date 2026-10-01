import Foundation

/// Ported from `OtpTimeoutBloc` (`lib/blocs/otp_timeout/bloc.dart`): a
/// 30-second, 1-second-tick countdown gating the OTP screen's resend button.
/// Dart drives this with `Timer.periodic` plus a `close()` guard against
/// firing `add` after the bloc is gone; a single cancellable `Task` gives the
/// same one-tick-per-second cadence with structured-concurrency cancellation
/// instead, so there's no separate "is this thing still alive" flag to
/// maintain by hand.
///
/// Numerically identical to the Dart source: `updatedSeconds = 30 -
/// event.seconds` there becomes `totalSeconds - tick` here, so
/// `secondsRemaining` walks 29, 28, ... 1, 0 over the same 30 real seconds.
///
/// Owned locally by `OTPView` (`@State`), same as Dart's
/// `BlocProvider(create: (_) => OtpTimeoutBloc())` creating one fresh per
/// `OtpScreen` instance rather than sharing it with `PhoneAuthViewModel`.
@MainActor
@Observable
final class OTPResendCountdown {
    private(set) var secondsRemaining = 0

    private var countdownTask: Task<Void, Never>?
    private static let totalSeconds = 30

    var canResend: Bool { secondsRemaining == 0 }

    /// `StartOtpTimeoutEvent` — (re)starts the countdown from 29, cancelling
    /// any countdown already in flight (matches `timer?.cancel()` before
    /// arming a new `Timer.periodic`).
    func start() {
        countdownTask?.cancel()
        secondsRemaining = 0

        countdownTask = Task { [weak self] in
            for tick in 1...Self.totalSeconds {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.secondsRemaining = max(0, Self.totalSeconds - tick)
            }
        }
    }

    /// Matches Dart's `close()` cancelling the periodic timer — called from
    /// `OTPView`'s `.onDisappear` so a countdown left running when the user
    /// backs out doesn't keep ticking against a view that's gone.
    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
    }
}
