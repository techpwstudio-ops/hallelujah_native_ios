import Foundation

protocol ClockProviding: Sendable {
    func now() -> Date
}

struct SystemClock: ClockProviding {
    func now() -> Date { Date() }
}

/// A test/preview double — returns the same instant every time.
struct FixedClock: ClockProviding {
    let date: Date

    func now() -> Date { date }
}
