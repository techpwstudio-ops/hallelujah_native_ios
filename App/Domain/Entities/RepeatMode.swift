import Foundation

/// Mirrors `just_audio`'s `LoopMode`, reused directly by `PlayerBlocState`
/// (`lib/blocs/player/state.dart:60`) rather than an app-defined enum in
/// Dart — its 3 cases and fixed cycle order are what this ports
/// (`_onLoopModeChanged`, `bloc.dart:2002-2033`: a single button cycles
/// off -> all -> one -> off, not 3 independently-selectable modes).
enum RepeatMode: String, Sendable, Equatable, Codable {
    case off
    case all
    case one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}
