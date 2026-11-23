import XCTest
@testable import Wallnetic

/// The language choice in Settings > General (#351).
final class AppLanguageTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppLanguageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeSettings() -> AppLanguageSettings {
        AppLanguageSettings(defaults: defaults, domain: suiteName)
    }

    func testWithoutAChoiceTheAppFollowsTheSystem() {
        let settings = makeSettings()
        XCTAssertEqual(settings.selection, .system)
        XCTAssertFalse(settings.needsRestart)
    }

    func testAChoiceIsStoredAsTheAppsLanguageListAndNeedsARestart() {
        let settings = makeSettings()
        settings.select(.german)
        XCTAssertEqual(settings.selection, .german)
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName)?[AppLanguageSettings.key] as? [String], ["de"])
        XCTAssertTrue(settings.needsRestart, "The running app keeps the language it started with")

        // What the next start reads.
        let next = makeSettings()
        XCTAssertEqual(next.selection, .german)
        XCTAssertFalse(next.needsRestart)
    }

    func testSystemDefaultRemovesTheAppsOwnList() {
        defaults.set(["ja"], forKey: AppLanguageSettings.key)
        let settings = makeSettings()
        XCTAssertEqual(settings.selection, .japanese)

        settings.select(.system)
        XCTAssertEqual(settings.selection, .system)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[AppLanguageSettings.key])
        XCTAssertTrue(settings.needsRestart)

        settings.select(.japanese)
        XCTAssertFalse(settings.needsRestart, "Back at the language the app started with")
    }

    func testAStoredListIsReadByItsFirstLanguage() {
        XCTAssertEqual(AppLanguage(storedLanguages: nil), .system)
        XCTAssertEqual(AppLanguage(storedLanguages: []), .system)
        XCTAssertEqual(AppLanguage(storedLanguages: ["de-DE", "en"]), .german)
        XCTAssertEqual(AppLanguage(storedLanguages: ["fr_CA"]), .french)
        XCTAssertEqual(AppLanguage(storedLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage(storedLanguages: ["en-GB"]), .english)
        XCTAssertEqual(AppLanguage(storedLanguages: ["tr-TR", "de"]), .system,
                       "A language without a translation is not one of the choices")
        XCTAssertEqual(AppLanguage(storedLanguages: ["zh-Hant-TW"]), .system)
        XCTAssertEqual(AppLanguage(storedLanguages: ["system"]), .system)
    }

    func testEveryChoiceHasANameAndTheLanguagesUseTheirOwn() {
        XCTAssertEqual(AppLanguage.german.title, "Deutsch")
        XCTAssertEqual(AppLanguage.japanese.title, "日本語")
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.title)).count, AppLanguage.allCases.count)
    }
}
