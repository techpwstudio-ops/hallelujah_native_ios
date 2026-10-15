import Foundation
import Testing
@testable import GHallelujah

struct PushPayloadTests {
    @Test func verseOfDayPushesAreRecognised() {
        #expect(PushPayload.verseOfDayID(from: ["topic": "verse_of_day", "verseOfDayId": "v9"]) == "v9")
        #expect(PushPayload.verseOfDayID(from: ["topic": "verse_of_day"]) == nil)
        #expect(PushPayload.verseOfDayID(from: ["topic": "other", "verseOfDayId": "v9"]) == nil)
    }

    @Test func jsonStringDataIsDecodedAndEventExtracted() throws {
        let event = try #require(PushPayload.realtimeEvent(
            from: ["event": "premium.member.invite", "data": #"{"inviteId":"i1","planName":"Family"}"#],
            currentUserID: "u1"
        ))
        #expect(event.name == "premium.member.invite")
        let data = try #require(event.envelope["data"] as? [String: Any])
        #expect(data["inviteId"] as? String == "i1")
    }

    @Test func adminPushesWithoutAnEventAreNotDispatched() {
        #expect(PushPayload.realtimeEvent(
            from: ["type": "admin", "shareableType": "song", "shareableId": "s1"],
            currentUserID: "u1"
        ) == nil)
        #expect(PushPayload.realtimeEvent(from: ["event": ""], currentUserID: "u1") == nil)
    }

    @Test func pushesForAnotherAccountAreDropped() {
        let payload: [AnyHashable: Any] = ["event": "users.user.updated", "fcmToken": "user-someone-else"]
        #expect(PushPayload.realtimeEvent(from: payload, currentUserID: "u1") == nil)
        let own: [AnyHashable: Any] = ["event": "users.user.updated", "fcmToken": "user-u1"]
        #expect(PushPayload.realtimeEvent(from: own, currentUserID: "u1") != nil)
        let topic: [AnyHashable: Any] = ["event": "songs.public", "fcmToken": "song_updates"]
        #expect(PushPayload.realtimeEvent(from: topic, currentUserID: nil) != nil)
    }

    @Test func nonStringKeysAreIgnored() {
        let event = PushPayload.realtimeEvent(from: [1: "x", "event": "premium.update"], currentUserID: nil)
        #expect(event?.name == "premium.update")
    }

    @Test func deduplicatorLetsEachIDThroughOnce() {
        let dedup = PushDeduplicator(capacity: 2)
        #expect(dedup.isFirstSighting(of: "a"))
        #expect(!dedup.isFirstSighting(of: "a"))
        #expect(dedup.isFirstSighting(of: nil))
        #expect(dedup.isFirstSighting(of: nil))
        #expect(dedup.isFirstSighting(of: "b"))
        #expect(dedup.isFirstSighting(of: "c")) // evicts "a"
        #expect(dedup.isFirstSighting(of: "a"))
    }
}
