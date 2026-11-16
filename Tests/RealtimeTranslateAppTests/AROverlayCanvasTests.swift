import XCTest
import CoreGraphics
import AVFAudio
import SwiftUI
@testable import RealtimeTranslateApp

final class AROverlayCanvasTests: XCTestCase {

    // MARK: - ARTextBadgeView State & Model Tests

    /// Tests that ARTextBadgeView prefers translated text when available.
    func testBadgeViewDisplaysTranslatedTextWhenAvailable() {
        let badge = ARTextBadgeView(
            originalText: "牛肉面",
            translatedText: "Mie Daging Sapi",
            isSelected: false,
            targetLanguageCode: "id"
        )

        XCTAssertTrue(badge.hasTranslation)
        XCTAssertEqual(badge.displayText, "Mie Daging Sapi")
        XCTAssertEqual(badge.languageBadgeText, "ID")
        XCTAssertFalse(badge.isSelected)
    }

    /// Tests that ARTextBadgeView falls back to original text when translation is nil or empty.
    func testBadgeViewFallsBackToOriginalTextWhenTranslationIsNilOrEmpty() {
        // Case 1: Nil translation
        let badgeNil = ARTextBadgeView(
            originalText: "炒饭",
            translatedText: nil
        )
        XCTAssertFalse(badgeNil.hasTranslation)
        XCTAssertEqual(badgeNil.displayText, "炒饭")

        // Case 2: Empty translation
        let badgeEmpty = ARTextBadgeView(
            originalText: "炒饭",
            translatedText: "   "
        )
        XCTAssertFalse(badgeEmpty.hasTranslation)
        XCTAssertEqual(badgeEmpty.displayText, "炒饭")
    }

    /// Tests badge initialization from TrackedTextBlock.
    func testBadgeViewInitializesFromTrackedTextBlock() {
        let block = TrackedTextBlock(
            rawLines: ["欢迎光临"],
            mergedText: "欢迎光临",
            boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1),
            translatedText: "Selamat Datang",
            sourceLanguage: "zh"
        )

        let badge = ARTextBadgeView(block: block, isSelected: true, targetLanguageCode: "id")
        XCTAssertTrue(badge.isSelected)
        XCTAssertTrue(badge.hasTranslation)
        XCTAssertEqual(badge.displayText, "Selamat Datang")
        XCTAssertEqual(badge.languageBadgeText, "ID")
    }

    /// Tests badge initialization from DetectedTextBlock.
    func testBadgeViewInitializesFromDetectedTextBlock() {
        let detected = DetectedTextBlock(
            rawLines: ["水饺"],
            mergedText: "水饺",
            boundingBox: CGRect(x: 0.2, y: 0.5, width: 0.2, height: 0.05),
            translatedText: "Pangsit Air",
            sourceLanguage: "zh"
        )

        let badge = ARTextBadgeView(block: detected, isSelected: false)
        XCTAssertFalse(badge.isSelected)
        XCTAssertTrue(badge.hasTranslation)
        XCTAssertEqual(badge.displayText, "Pangsit Air")
    }

    // MARK: - Romanization & Pinyin Transliteration Tests

    /// Tests phonetic Pinyin generation for standard Mandarin phrases with tone marks.
    func testRomanizationHelperGeneratesPinyinWithDiacritics() {
        // "你好" -> "nǐ hǎo"
        let nihao = RomanizationHelper.romanize("你好")
        XCTAssertNotNil(nihao)
        XCTAssertTrue(nihao?.contains("hǎo") == true || nihao?.contains("nǐ") == true, "Expected pinyin with tone marks, got: \(nihao ?? "")")

        // "牛肉面" -> "niú ròu miàn"
        let beefNoodles = RomanizationHelper.romanize("牛肉面")
        XCTAssertNotNil(beefNoodles)
        XCTAssertTrue(beefNoodles?.contains("miàn") == true || beefNoodles?.contains("niú") == true, "Expected pinyin for 牛肉面, got: \(beefNoodles ?? "")")

        // "欢迎光临" -> "huān yíng guāng lín"
        let welcome = RomanizationHelper.romanize("欢迎光临")
        XCTAssertNotNil(welcome)
        XCTAssertTrue(welcome?.contains("huān") == true || welcome?.contains("yíng") == true, "Expected pinyin for 欢迎光临, got: \(welcome ?? "")")
    }

    /// Tests stripping tone marks / diacritics for ASCII-safe Pinyin output.
    func testRomanizationHelperStripsDiacritics() {
        let strippedNihao = RomanizationHelper.romanize("你好", stripDiacritics: true)
        XCTAssertNotNil(strippedNihao)
        XCTAssertEqual(strippedNihao?.lowercased(), "ni hao")

        let strippedBeef = RomanizationHelper.romanize("牛肉面", stripDiacritics: true)
        XCTAssertNotNil(strippedBeef)
        XCTAssertEqual(strippedBeef?.lowercased(), "niu rou mian")
    }

    /// Tests that pure Latin / English text returns nil because no transliteration is needed.
    func testRomanizationHelperReturnsNilForLatinText() {
        XCTAssertNil(RomanizationHelper.romanize("Hello World"))
        XCTAssertNil(RomanizationHelper.romanize("Selamat Datang di Restoran"))
        XCTAssertNil(RomanizationHelper.romanize("Special Lunch Menu 2026"))
    }

    /// Tests that empty or whitespace strings return nil.
    func testRomanizationHelperReturnsNilForEmptyOrBlankStrings() {
        XCTAssertNil(RomanizationHelper.romanize(""))
        XCTAssertNil(RomanizationHelper.romanize("   \n\t  "))
    }

    /// Tests hasRomanization helper method.
    func testHasRomanizationHelper() {
        XCTAssertTrue(RomanizationHelper.hasRomanization(for: "小笼包"))
        XCTAssertTrue(RomanizationHelper.hasRomanization(for: "东京"))
        XCTAssertFalse(RomanizationHelper.hasRomanization(for: "Coffee & Tea"))
        XCTAssertFalse(RomanizationHelper.hasRomanization(for: ""))
    }

    // MARK: - Text-to-Speech (TTS) Configuration Tests

    /// Tests voice resolution for common language codes.
    func testTTSVoiceResolution() {
        // Chinese Simplified voice
        let zhVoice = TextToSpeechManager.resolveVoice(for: "zh-Hans")
        XCTAssertNotNil(zhVoice)
        XCTAssertTrue(zhVoice?.language.lowercased().starts(with: "zh") == true)

        let zhShortVoice = TextToSpeechManager.resolveVoice(for: "zh")
        XCTAssertNotNil(zhShortVoice)
        XCTAssertTrue(zhShortVoice?.language.lowercased().starts(with: "zh") == true)

        // Indonesian voice
        let idVoice = TextToSpeechManager.resolveVoice(for: "id")
        XCTAssertNotNil(idVoice)
        XCTAssertTrue(idVoice?.language.lowercased().starts(with: "id") == true)

        // English voice
        let enVoice = TextToSpeechManager.resolveVoice(for: "en")
        XCTAssertNotNil(enVoice)
        XCTAssertTrue(enVoice?.language.lowercased().starts(with: "en") == true)

        // Japanese voice
        let jaVoice = TextToSpeechManager.resolveVoice(for: "ja")
        XCTAssertNotNil(jaVoice)
        XCTAssertTrue(jaVoice?.language.lowercased().starts(with: "ja") == true)
    }

    /// Tests speech utterance configuration.
    func testTTSMakeUtterance() {
        let text = "红烧牛肉面"
        let rate: Float = 0.45
        let utterance = TextToSpeechManager.makeUtterance(
            text: text,
            languageCode: "zh-CN",
            rate: rate
        )

        XCTAssertEqual(utterance.speechString, text)
        XCTAssertEqual(utterance.rate, rate, accuracy: 0.001)
        XCTAssertEqual(utterance.pitchMultiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(utterance.volume, 1.0, accuracy: 0.001)
        XCTAssertNotNil(utterance.voice)
        XCTAssertTrue(utterance.voice?.language.lowercased().starts(with: "zh") == true)
    }

    // MARK: - AROverlayCanvas Coordinate Calculation Tests

    /// Tests that normalized Vision bounding boxes are converted to screen coordinates.
    func testOverlayCanvasConvertsNormalizedVisionBoundingBoxes() {
        let canvas = AROverlayCanvas(
            trackedBlocks: [],
            videoAspectRatio: 0.5,
            onSelectBlock: { _ in }
        )

        // Normalized Vision rect: x: 0.1, y: 0.8, w: 0.3, h: 0.1
        let normalizedBlock = TrackedTextBlock(
            rawLines: ["Test"],
            mergedText: "Test",
            boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1)
        )

        let viewSize = CGSize(width: 400, height: 800) // ratio 0.5 matches video ratio
        let screenRect = canvas.computeScreenRect(for: normalizedBlock, in: viewSize)

        // Screen coordinates:
        // x = 0.1 * 400 = 40
        // y = (1.0 - 0.8 - 0.1) * 800 = 80
        // width = 0.3 * 400 = 120
        // height = 0.1 * 800 = 80
        XCTAssertEqual(screenRect.origin.x, 40, accuracy: 0.001)
        XCTAssertEqual(screenRect.origin.y, 80, accuracy: 0.001)
        XCTAssertEqual(screenRect.width, 120, accuracy: 0.001)
        XCTAssertEqual(screenRect.height, 80, accuracy: 0.001)
    }

    /// Tests that bounding boxes already in screen points bypass transformation.
    func testOverlayCanvasPreservesPreconvertedScreenCoordinates() {
        let canvas = AROverlayCanvas(
            trackedBlocks: [],
            onSelectBlock: { _ in }
        )

        let preconvertedBlock = TrackedTextBlock(
            rawLines: ["Screen Block"],
            mergedText: "Screen Block",
            boundingBox: CGRect(x: 120, y: 350, width: 180, height: 45)
        )

        let viewSize = CGSize(width: 393, height: 852)
        let screenRect = canvas.computeScreenRect(for: preconvertedBlock, in: viewSize)

        XCTAssertEqual(screenRect.origin.x, 120, accuracy: 0.001)
        XCTAssertEqual(screenRect.origin.y, 350, accuracy: 0.001)
        XCTAssertEqual(screenRect.width, 180, accuracy: 0.001)
        XCTAssertEqual(screenRect.height, 45, accuracy: 0.001)
    }

    /// Tests that degenerate container sizes safely return .zero.
    func testOverlayCanvasHandlesDegenerateSizes() {
        let canvas = AROverlayCanvas(trackedBlocks: [], onSelectBlock: { _ in })
        let block = TrackedTextBlock(
            rawLines: ["Test"],
            mergedText: "Test",
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1)
        )

        XCTAssertEqual(canvas.computeScreenRect(for: block, in: .zero), .zero)
        XCTAssertEqual(canvas.computeScreenRect(for: block, in: CGSize(width: 0, height: 500)), .zero)
    }

    // MARK: - DetailCardSheet Model & Presentation Tests

    /// Tests DetailCardSheet metadata derivation.
    func testDetailCardSheetMetadata() {
        let block = TrackedTextBlock(
            rawLines: ["麻婆豆腐"],
            mergedText: "麻婆豆腐",
            boundingBox: CGRect(x: 50, y: 100, width: 120, height: 35),
            translatedText: "Tahu Mapo",
            sourceLanguage: "zh-Hans"
        )

        let sheet = DetailCardSheet(
            block: block,
            targetLanguage: .indonesian
        )

        // Verifies language matching
        XCTAssertEqual(sheet.sourceLanguage.bcp47Code, "zh-Hans")
        XCTAssertEqual(sheet.targetLanguage.bcp47Code, "id")
        XCTAssertEqual(sheet.sourceVoiceLanguageCode, "zh-Hans")
        XCTAssertEqual(sheet.targetVoiceLanguageCode, "id")

        // Verifies copy string prefers translated text
        XCTAssertEqual(sheet.textToCopy, "Tahu Mapo")

        // Verifies romanization exists
        XCTAssertNotNil(sheet.romanizedText)
        XCTAssertTrue(sheet.romanizedText?.lowercased().contains("m") == true)
    }

    /// Tests DetailCardSheet copy text fallback when translation is missing.
    func testDetailCardSheetCopyTextFallback() {
        let block = TrackedTextBlock(
            rawLines: ["Unfinished"],
            mergedText: "Unfinished",
            boundingBox: CGRect(x: 10, y: 10, width: 80, height: 20),
            translatedText: nil,
            sourceLanguage: "en"
        )

        let sheet = DetailCardSheet(block: block)
        XCTAssertEqual(sheet.textToCopy, "Unfinished")
    }

    /// Tests DetailCardSheet initialization with DetectedTextBlock.
    func testDetailCardSheetInitializesFromDetectedTextBlock() {
        let detected = DetectedTextBlock(
            rawLines: ["宫保鸡丁"],
            mergedText: "宫保鸡丁",
            boundingBox: CGRect(x: 10, y: 20, width: 100, height: 30),
            translatedText: "Ayam Kung Pao",
            sourceLanguage: "zh"
        )

        let sheet = DetailCardSheet(detectedBlock: detected)
        XCTAssertEqual(sheet.block.mergedText, "宫保鸡丁")
        XCTAssertEqual(sheet.block.translatedText, "Ayam Kung Pao")
        XCTAssertEqual(sheet.textToCopy, "Ayam Kung Pao")
    }
}
