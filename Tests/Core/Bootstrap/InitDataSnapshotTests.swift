import Foundation
import Testing
@testable import GHallelujah

struct InitDataSnapshotTests {
    private func parse(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func parsesTopicsBookLanguagesAndLanguages() throws {
        let json = try parse("""
        {"topics":[{"id":"t1","name":"News","topicKey":"news","language":null},
                   {"id":"t2","name":"Songs","topicKey":"songs-te","language":"Telugu"},
                   {"name":"no id"}],
         "bookLanguages":[{"language":"English"},{"language":"Telugu"}],
         "languages":[{"id":"1","name":"Hindi"},{"id":"2","name":"Tamil"}]}
        """)
        let snapshot = InitDataSnapshot(json: json)
        #expect(snapshot.topics.map(\.topicKey) == ["news", "songs-te"])
        #expect(snapshot.topics[1].language == "Telugu")
        #expect(snapshot.bookLanguages == ["English", "Telugu"])
        #expect(snapshot.languages == ["Hindi", "Tamil"])
    }

    @Test func absentKeysLeaveEmptyLists() throws {
        let snapshot = InitDataSnapshot(json: try parse("{}"))
        #expect(snapshot == InitDataSnapshot())
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        var snapshot = InitDataSnapshot()
        snapshot.bookLanguages = ["English"]
        snapshot.topics = [.init(id: "1", name: "n", topicKey: "k", language: nil)]
        let decoded = try JSONDecoder().decode(InitDataSnapshot.self, from: try JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func parsesTheInvite() throws {
        let json = try parse(#"{"invite":{"id":"inv1","inviter":{"name":"Ana"},"subscription":{"planName":"Family"}}}"#)
        let invite = try #require(InitInviteInfo(json: json))
        #expect(invite.inviteId == "inv1")
        #expect(invite.inviterName == "Ana")
        #expect(invite.planName == "Family")
    }

    @Test func noInviteOrNoIDMeansNoSheet() throws {
        #expect(InitInviteInfo(json: try parse("{}")) == nil)
        #expect(InitInviteInfo(json: try parse(#"{"invite":{"inviter":{}}}"#)) == nil)
    }

    @Test func realtimeInvitePayload() {
        let invite = InitInviteInfo(realtimeData: ["inviteId": "i", "inviterName": "Bo", "planName": "Duo"])
        #expect(invite == InitInviteInfo(inviteId: "i", inviterName: "Bo", planName: "Duo"))
        #expect(InitInviteInfo(realtimeData: ["planName": "Duo"]) == nil)
    }
}

struct RemoteSettingsParsingTests {
    @Test func boolsAreParsedLikeDartTryParse() {
        let resolved = RemoteSettings.resolved(from: ["adsEnabled": "false", "showSubscription": true])
        #expect(!resolved.adsEnabled)
        #expect(resolved.showSubscription)
    }

    @Test func missingOrInvalidValuesFallBackToDefaults() {
        let resolved = RemoteSettings.resolved(from: ["adsEnabled": "maybe", "showSubscription": "TRUE"])
        #expect(resolved.adsEnabled) // default true
        #expect(!resolved.showSubscription) // Dart's tryParse is case-sensitive
    }

    @Test func cdnURLIsTakenWhenPresent() {
        #expect(RemoteSettings.resolved(from: ["cdnUrl": "https://cdn.example.com"]).cdnUrl == "https://cdn.example.com")
        #expect(RemoteSettings.resolved(from: ["cdnUrl": ""]).cdnUrl == RemoteSettings.defaults().cdnUrl)
    }

    @MainActor
    @Test func applyPersistsAndRestoreReadsItBack() {
        let store = InMemoryKeyValueStore()
        let original = RemoteSettings.current
        defer { RemoteSettings.current = original }

        RemoteSettings.apply(settings: ["showSubscription": true, "adsEnabled": false], store: store)
        #expect(RemoteSettings.current.showSubscription)

        RemoteSettings.current = RemoteSettings.defaults()
        RemoteSettings.restore(store: store)
        #expect(RemoteSettings.current.showSubscription)
        #expect(!RemoteSettings.current.adsEnabled)
    }
}
