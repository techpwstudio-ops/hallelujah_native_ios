import Foundation
import Testing
@testable import Hallelujah

/// Every suite that drives a real player nests in here. They share one audio
/// session and observe process-wide notifications (a posted media services
/// reset reaches every live engine), so they must never run side by side.
@MainActor
@Suite(.serialized)
struct LiveAudioEngineTests {}

/// Real-`AudioEngine` test support: local files stand in for streams, so no
/// network is involved. Junk bytes fail to load the way a refused stream does.
enum AudioFixtures {
    @MainActor
    static func makeEngine(folder: URL) -> AudioEngine {
        let engine = AudioEngine(
            proxyBaseURL: URL(string: "http://127.0.0.1:9/api")!,
            keyValueStore: InMemoryKeyValueStore(),
            batteryMonitor: FakeBatteryMonitor(isLowBattery: false),
            connectivityType: FakeConnectivity(currentConnectionType: nil),
            tokenProvider: NoTokenProvider()
        )
        engine.localFileURLProvider = { folder.appending(path: "\($0).wav") }
        return engine
    }

    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AudioFixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func writeSilence(seconds: Double, for song: Song, in folder: URL) throws {
        try silentWAV(seconds: seconds).write(to: folder.appending(path: "\(song.id).wav"))
    }

    static func writeJunk(for song: Song, in folder: URL) throws {
        try Data("not audio".utf8).write(to: folder.appending(path: "\(song.id).wav"))
    }

    @MainActor
    static func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("condition not met within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// 16-bit mono PCM at 8 kHz, all zeros.
    static func silentWAV(seconds: Double) -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize = UInt32(Double(sampleRate) * seconds) * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    @MainActor
    final class Counter {
        var count = 0
    }
}

struct NoTokenProvider: AuthTokenProviding {
    func currentAccessToken() async -> String? { nil }
    func refreshIfNeeded() async throws -> AuthTokens { throw CancellationError() }
}
