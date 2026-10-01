import Foundation

/// Ports `FaqModel` (`lib/river_pods/faqProvider.dart`) — one row rendered as
/// a disclosure group on `FAQView` (T71). Keeps the server's own `id`
/// (`support.controller.js`'s `getFAQs` select) as `Identifiable`'s key,
/// unlike `FaqModel` which has none and lets Flutter's `ListView.separated`
/// key off index instead.
struct FAQItem: Sendable, Equatable, Identifiable {
    let id: String
    let question: String
    let answer: String
}
