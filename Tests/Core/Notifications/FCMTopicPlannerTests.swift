import Testing
@testable import GHallelujah

struct FCMTopicPlannerTests {
    @Test func reachLanguagePrefersPrimaryThenFirstSelectedThenEnglish() {
        #expect(FCMTopicPlanner.reachLanguage(primaryLanguage: " Telugu ", languages: "Hindi,Tamil") == "telugu")
        #expect(FCMTopicPlanner.reachLanguage(primaryLanguage: nil, languages: "Hindi, Tamil") == "hindi")
        #expect(FCMTopicPlanner.reachLanguage(primaryLanguage: "  ", languages: "Tamil") == "tamil")
        #expect(FCMTopicPlanner.reachLanguage(primaryLanguage: nil, languages: nil) == "english")
        #expect(FCMTopicPlanner.reachLanguage(primaryLanguage: nil, languages: "") == "english")
    }

    @Test func parseLanguagesTrimsLowercasesAndDropsEmpties() {
        #expect(FCMTopicPlanner.parseLanguages(" Hindi , ,Tamil,") == ["hindi", "tamil"])
        #expect(FCMTopicPlanner.parseLanguages(nil) == [])
    }

    @Test func globalTopicsAreAlwaysEligible() {
        #expect(FCMTopicPlanner.isEligible(topicLanguage: nil, reachLanguage: "hindi"))
        #expect(FCMTopicPlanner.isEligible(topicLanguage: "", reachLanguage: "hindi"))
        #expect(FCMTopicPlanner.isEligible(topicLanguage: "Hindi", reachLanguage: "hindi"))
        #expect(!FCMTopicPlanner.isEligible(topicLanguage: "Telugu", reachLanguage: "hindi"))
    }

    @Test func languageScopedPlanSubscribesEligibleAndEnabledOnly() {
        let topics: [(key: String?, language: String?)] = [
            ("news", nil),
            ("telugu-songs", "Telugu"),
            ("hindi-songs", "Hindi"),
            ("promos", nil),
            (nil, nil),
            ("", "Hindi"),
        ]
        let plan = FCMTopicPlanner.languageScopedPlan(
            topics: topics,
            reachLanguage: "hindi",
            isTopicEnabled: { $0 != "promos" }
        )
        #expect(plan.subscribe == ["news", "hindi-songs"])
        #expect(plan.unsubscribe == ["telugu-songs", "promos"])
    }

    @Test func verseOfDayJoinsBaseAndPerLanguageTopics() {
        let plan = FCMTopicPlanner.verseOfDayPlan(
            isDevelopment: false,
            bibleLanguage: "Telugu",
            bookLanguages: ["English", "Telugu"],
            notificationsEnabled: true
        )
        #expect(plan.subscribe == ["verse_of_day", "verse_of_daytelugu"])
        #expect(plan.unsubscribe == ["verse_of_dayenglish", "verse_of_daytelugu"])
    }

    @Test func verseOfDayDefaultsToEnglishAndHonoursTheOptOut() {
        let off = FCMTopicPlanner.verseOfDayPlan(
            isDevelopment: false,
            bibleLanguage: nil,
            bookLanguages: [],
            notificationsEnabled: false
        )
        #expect(off.subscribe.isEmpty)
        #expect(off.unsubscribe == ["verse_of_day", "verse_of_dayenglish"])
    }

    @Test func developmentUsesTheDevVerseTopicAndLeavesProduction() {
        let plan = FCMTopicPlanner.verseOfDayPlan(
            isDevelopment: true,
            bibleLanguage: "english",
            bookLanguages: ["English"],
            notificationsEnabled: true
        )
        #expect(plan.subscribe == ["verse_of_day_dev", "verse_of_day_devenglish"])
        #expect(plan.unsubscribe.contains("verse_of_dayenglish"))
        #expect(plan.unsubscribe.contains("verse_of_day"))
    }

    @Test func userTopicsFollowTheEnvironment() {
        #expect(FCMTopicPlanner.userTopics(userID: "u1", isDevelopment: false) == ["users", "user-u1"])
        #expect(FCMTopicPlanner.userTopics(userID: "u1", isDevelopment: true) == ["users_dev", "user-u1"])
        #expect(FCMTopicPlanner.userTopics(userID: nil, isDevelopment: false) == ["users"])
    }

    @Test func contentLanguagePlanLeavesAllThenJoinsSelected() {
        let plan = FCMTopicPlanner.contentLanguagePlan(allLanguages: ["Hindi", "Tamil"], selected: ["tamil"])
        #expect(plan.unsubscribe == ["user-lang-hindi", "user-lang-tamil"])
        #expect(plan.subscribe == ["user-lang-tamil"])
    }

    @Test func topicNamesAreValidatedLikeFirebase() {
        #expect(FCMTopicPlanner.isValidTopicName("verse_of_day"))
        #expect(FCMTopicPlanner.isValidTopicName("user-lang-hindi"))
        #expect(!FCMTopicPlanner.isValidTopicName("Daily Verse"))
        #expect(!FCMTopicPlanner.isValidTopicName(""))
    }
}
