import Foundation
import OSLog

/// Thin wrapper over `os.Logger` that additionally gates on the environment's
/// `LOG_LEVEL` (from `AppConfiguration`, not the OS's own log-level filtering).
struct AppLogger: Sendable {
    let category: LogCategory
    let minimumLevel: LogLevel

    private let osLogger: Logger

    init(category: LogCategory, minimumLevel: LogLevel) {
        self.category = category
        self.minimumLevel = minimumLevel
        osLogger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    init(category: LogCategory, configuration: AppConfiguration = .current) {
        self.init(
            category: category,
            minimumLevel: LogLevel(rawValue: configuration.logLevel) ?? .warning
        )
    }

    func isEnabled(for level: LogLevel) -> Bool {
        level >= minimumLevel
    }

    func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    func error(_ message: @autoclosure () -> String) { log(.error, message()) }

    private func log(_ level: LogLevel, _ message: String) {
        guard isEnabled(for: level) else { return }
        switch level {
        case .debug: osLogger.debug("\(message, privacy: .public)")
        case .info: osLogger.info("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        case .error: osLogger.error("\(message, privacy: .public)")
        }
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.hallelujah.user"
}
