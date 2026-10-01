/// One case per subsystem that actually logs something. Add a case when a
/// new subsystem needs one (T05 networking, T06 auth, …) rather than
/// pre-declaring categories nothing uses yet.
enum LogCategory: String {
    case app
    case configuration
    case dependencyInjection
    case networking
    case security
    case analytics
    case launch
    case deepLinking
    case authentication
    case content
    case playback
    case notifications
    case realtime
    case sharing
    case subscription
    case carPlay
    case tips
    case ads
}
