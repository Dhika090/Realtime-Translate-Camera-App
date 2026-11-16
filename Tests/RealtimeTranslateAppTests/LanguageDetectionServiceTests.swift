import XCTest
@testable import RealtimeTranslateApp

final class LanguageDetectionServiceTests: XCTestCase {

    // MARK: - Language Detection Tests

    func testDetectsChineseScript() {
        let detector = LanguageDetectionService()
        let lang = detector.detectDominantLanguage(text: "欢迎光临 餐厅")
        XCTAssertEqual(lang?.languageCode?.identifier, "zh")

        let beefNoodle = detector.detectDominantLanguage(text: "红烧牛肉面")
        XCTAssertEqual(beefNoodle?.languageCode?.identifier, "zh")
    }

    func testDetectsIndonesianScript() {
        let detector = LanguageDetectionService()
        let lang = detector.detectDominantLanguage(text: "Selamat Datang di Restoran Kami")
        XCTAssertEqual(lang?.languageCode?.identifier, "id")

        let menuText = detector.detectDominantLanguage(text: "Daftar menu makanan dan minuman segar")
        XCTAssertEqual(menuText?.languageCode?.identifier, "id")
    }

    func testDetectsEnglishScript() {
        let detector = LanguageDetectionService()
        let lang = detector.detectDominantLanguage(text: "Fresh roast beef and coffee")
        XCTAssertEqual(lang?.languageCode?.identifier, "en")

        let specialLunch = detector.detectDominantLanguage(text: "Special Lunch Menu Today Only")
        XCTAssertEqual(specialLunch?.languageCode?.identifier, "en")
    }

    func testEmptyOrWhitespaceReturnsNil() {
        let detector = LanguageDetectionService()
        XCTAssertNil(detector.detectDominantLanguage(text: ""))
        XCTAssertNil(detector.detectDominantLanguage(text: "    "))
        XCTAssertNil(detector.detectDominantLanguage(text: "\n\t  \r\n"))
    }

    func testDetectLanguageCodeConvenience() {
        let detector = LanguageDetectionService()
        XCTAssertEqual(detector.detectLanguageCode(text: "欢迎光临"), "zh")
        XCTAssertEqual(detector.detectLanguageCode(text: "Selamat pagi semua"), "id")
        XCTAssertEqual(detector.detectLanguageCode(text: "Good morning everyone"), "en")
        XCTAssertNil(detector.detectLanguageCode(text: "   "))
    }

    func testDetectAppLanguagePreset() {
        let detector = LanguageDetectionService()
        let chineseAppLang = detector.detectAppLanguage(text: "欢迎光临 餐厅")
        XCTAssertEqual(chineseAppLang?.bcp47Code, "zh-Hans")
        XCTAssertEqual(chineseAppLang?.flagEmoji, "🇨🇳")

        let indonesianAppLang = detector.detectAppLanguage(text: "Selamat Datang di Restoran Kami")
        XCTAssertEqual(indonesianAppLang?.bcp47Code, "id")
        XCTAssertEqual(indonesianAppLang?.flagEmoji, "🇮🇩")

        let englishAppLang = detector.detectAppLanguage(text: "Fresh roast beef and coffee")
        XCTAssertEqual(englishAppLang?.bcp47Code, "en")
        XCTAssertEqual(englishAppLang?.flagEmoji, "🇺🇸")
    }

    // MARK: - LanguagePair & AppLanguage Model Tests

    func testAppLanguagePresets() {
        XCTAssertTrue(AppLanguage.autoDetect.isAutoDetect)
        XCTAssertNil(AppLanguage.autoDetect.localeLanguage)
        XCTAssertEqual(AppLanguage.autoDetect.flagEmoji, "🌐")

        XCTAssertFalse(AppLanguage.indonesian.isAutoDetect)
        XCTAssertEqual(AppLanguage.indonesian.bcp47Code, "id")
        XCTAssertEqual(AppLanguage.indonesian.localeLanguage?.languageCode?.identifier, "id")

        XCTAssertEqual(AppLanguage.simplifiedChinese.bcp47Code, "zh-Hans")
        XCTAssertEqual(AppLanguage.traditionalChinese.bcp47Code, "zh-Hant")
        XCTAssertEqual(AppLanguage.english.bcp47Code, "en")

        XCTAssertTrue(AppLanguage.sourceLanguages.contains(where: { $0.isAutoDetect }))
        XCTAssertFalse(AppLanguage.targetLanguages.contains(where: { $0.isAutoDetect }))
    }

    func testAppLanguageResolution() {
        XCTAssertEqual(AppLanguage.from(code: "zh"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.from(code: "zh-Hans"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.from(code: "zh-Hant"), .traditionalChinese)
        XCTAssertEqual(AppLanguage.from(code: "id"), .indonesian)
        XCTAssertEqual(AppLanguage.from(code: "en"), .english)
        XCTAssertEqual(AppLanguage.from(code: "auto"), .autoDetect)
        XCTAssertNil(AppLanguage.from(code: ""))
    }

    func testLanguagePairPresets() {
        let defaultPair = LanguagePair.defaultPair
        XCTAssertTrue(defaultPair.isAutoDetect)
        XCTAssertEqual(defaultPair.target.bcp47Code, "id")

        let chineseToID = LanguagePair.chineseToIndonesian
        XCTAssertFalse(chineseToID.isAutoDetect)
        XCTAssertEqual(chineseToID.source.bcp47Code, "zh-Hans")
        XCTAssertEqual(chineseToID.target.bcp47Code, "id")
        XCTAssertEqual(chineseToID.id, "zh-Hans_id")

        XCTAssertEqual(LanguagePair.presetPairs.count, 6)
        XCTAssertTrue(LanguagePair.presetPairs.contains(LanguagePair.autoToIndonesian))
        XCTAssertTrue(LanguagePair.presetPairs.contains(LanguagePair.chineseToIndonesian))
    }

    // MARK: - TranslationService Tests

    func testTranslationServiceAvailabilityCheck() async {
        let service = TranslationService()
        let target = Locale.Language(identifier: "id")
        let source = Locale.Language(identifier: "zh-Hans")

        let status = await service.checkAvailability(from: source, to: target)
        XCTAssertTrue(status == .supported || status == .installed)
    }

    func testTranslationServiceCustomAvailabilityHandler() async {
        let service = TranslationService(availabilityHandler: { _, _ in
            return .installed
        })

        let status = await service.checkAvailability(
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "id")
        )
        XCTAssertEqual(status, .installed)
    }

    func testTranslationServiceBuiltInSimulatedFallback() async throws {
        let service = TranslationService(forceFallback: true)
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: "id")

        let results = try await service.translate(
            texts: ["欢迎光临 餐厅", "红烧牛肉面"],
            source: source,
            target: target
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], "Selamat Datang di Restoran")
        XCTAssertEqual(results[1], "Mie Daging Sapi Rebus Merah")
    }

    func testTranslationServiceWithCustomAdapter() async throws {
        struct MockAdapter: TranslationSessionAdapter {
            func translate(batch texts: [String]) async throws -> [String] {
                return texts.map { "MOCK: \($0)" }
            }
        }

        let service = TranslationService(sessionAdapter: MockAdapter())
        let results = try await service.translate(
            texts: ["Hello", "World"],
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "id")
        )

        XCTAssertEqual(results, ["MOCK: Hello", "MOCK: World"])
    }

    func testTranslationServiceWithCustomFallbackHandler() async throws {
        let service = TranslationService(fallbackHandler: { texts, _, _ in
            return texts.map { "CUSTOM_FALLBACK: \($0)" }
        })

        let results = try await service.translate(
            texts: ["Test Item"],
            source: nil,
            target: Locale.Language(identifier: "id")
        )

        XCTAssertEqual(results, ["CUSTOM_FALLBACK: Test Item"])
    }

    func testTranslationServiceEmptyInputReturnsEmpty() async throws {
        let service = TranslationService()
        let results = try await service.translate(
            texts: [],
            source: nil,
            target: Locale.Language(identifier: "id")
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testTranslationServiceSingleTextConvenience() async throws {
        let service = TranslationService(forceFallback: true)
        let singleResult = try await service.translate(
            text: "Fresh roast beef and coffee",
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "id")
        )

        XCTAssertEqual(singleResult, "Daging sapi panggang segar dan kopi")
    }
}
