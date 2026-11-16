import XCTest
import CoreGraphics
import CoreVideo
import Combine
import AVFoundation
@testable import RealtimeTranslateApp

// MARK: - Test Doubles & Mocks

final class MockOCRServiceForVM: OCRServiceProtocol, @unchecked Sendable {
    var configuration: OCRConfiguration = .default
    var throttler: FrameThrottler = FrameThrottler(minimumInterval: 0.0)
    var blocksToReturn: [DetectedTextBlock] = []
    var shouldFail: Bool = false
    var shouldThrottle: Bool = false
    var processCallCount: Int = 0

    func shouldProcessFrame() -> Bool {
        !shouldThrottle
    }

    func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        ignoreThrottling: Bool
    ) async throws -> [DetectedTextBlock] {
        processCallCount += 1
        if shouldFail {
            throw OCRError.recognitionFailed("Simulated OCR failure")
        }
        return blocksToReturn
    }

    func process(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        ignoreThrottling: Bool
    ) async throws -> [DetectedTextBlock] {
        processCallCount += 1
        if shouldFail {
            throw OCRError.recognitionFailed("Simulated OCR failure")
        }
        return blocksToReturn
    }
}

final class MockTranslationServiceForVM: TranslationServiceProtocol, @unchecked Sendable {
    var availabilityStatus: TranslationAvailabilityStatus = .installed
    var mockTranslations: [String: String] = [:]
    var translateCallCount: Int = 0
    var shouldFail: Bool = false
    var lastSourceLocale: Locale.Language?
    var lastTargetLocale: Locale.Language?

    func checkAvailability(
        from source: Locale.Language?,
        to target: Locale.Language
    ) async -> TranslationAvailabilityStatus {
        availabilityStatus
    }

    func translate(
        texts: [String],
        source: Locale.Language?,
        target: Locale.Language
    ) async throws -> [String] {
        translateCallCount += 1
        lastSourceLocale = source
        lastTargetLocale = target

        if shouldFail {
            throw TranslationServiceError.translationFailed("Simulated Translation failure")
        }

        return texts.map { mockTranslations[$0] ?? "Terjemahan \($0)" }
    }
}

// MARK: - Pixel Buffer Helper

private func createTestPixelBuffer(width: Int = 100, height: Int = 100) -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attrs = [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
    ] as CFDictionary
    CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs,
        &pixelBuffer
    )
    return pixelBuffer!
}

// MARK: - CameraTranslationViewModelTests

@MainActor
final class CameraTranslationViewModelTests: XCTestCase {

    var viewModel: CameraTranslationViewModel!
    var mockOCR: MockOCRServiceForVM!
    var mockTranslation: MockTranslationServiceForVM!
    var mockTorch: MockTorchController!
    var cameraManager: CameraCaptureManager!
    var boxTracker: BoxTracker!
    var languageDetector: LanguageDetectionService!

    override func setUp() async throws {
        mockOCR = MockOCRServiceForVM()
        mockTranslation = MockTranslationServiceForVM()
        mockTorch = MockTorchController()
        cameraManager = CameraCaptureManager(torchController: mockTorch)
        boxTracker = BoxTracker()
        languageDetector = LanguageDetectionService()

        viewModel = CameraTranslationViewModel(
            cameraManager: cameraManager,
            ocrService: mockOCR,
            translationService: mockTranslation,
            languageDetectionService: languageDetector,
            boxTracker: boxTracker,
            sourceLanguage: .auto,
            targetLanguage: .indonesian
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        mockOCR = nil
        mockTranslation = nil
        mockTorch = nil
        cameraManager = nil
        boxTracker = nil
        languageDetector = nil
    }

    // MARK: - 1. Initial State Tests

    func testInitialStateDefaults() {
        XCTAssertTrue(viewModel.trackedBlocks.isEmpty)
        XCTAssertNil(viewModel.selectedBlock)
        XCTAssertEqual(viewModel.sourceLanguage, .auto)
        XCTAssertEqual(viewModel.targetLanguage, .indonesian)
        XCTAssertNil(viewModel.detectedDominantLanguage)
        XCTAssertFalse(viewModel.isFrozen)
        XCTAssertFalse(viewModel.isTorchOn)
        XCTAssertFalse(viewModel.showOnboardingSheet)
        XCTAssertFalse(viewModel.showDetailSheet)
        XCTAssertFalse(viewModel.isTranslating)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - 2. Language Selection & Switching Tests

    func testSetSourceLanguageUpdatesState() {
        viewModel.setSourceLanguage(.simplifiedChinese)
        XCTAssertEqual(viewModel.sourceLanguage, .simplifiedChinese)
        XCTAssertNil(viewModel.detectedDominantLanguage)
    }

    func testSetTargetLanguageUpdatesState() {
        viewModel.setTargetLanguage(.english)
        XCTAssertEqual(viewModel.targetLanguage, .english)
    }

    func testSwapLanguagesWithConcreteLanguages() {
        viewModel.setSourceLanguage(.english)
        viewModel.setTargetLanguage(.indonesian)

        viewModel.swapLanguages()

        XCTAssertEqual(viewModel.sourceLanguage, .indonesian)
        XCTAssertEqual(viewModel.targetLanguage, .english)
    }

    func testSwapLanguagesWhenAutoDetectWithDetectedDominantLanguage() {
        viewModel.setSourceLanguage(.auto)
        viewModel.setTargetLanguage(.indonesian)
        viewModel.detectedDominantLanguage = .simplifiedChinese

        viewModel.swapLanguages()

        XCTAssertEqual(viewModel.sourceLanguage, .indonesian)
        XCTAssertEqual(viewModel.targetLanguage, .simplifiedChinese)
        XCTAssertNil(viewModel.detectedDominantLanguage)
    }

    func testSwapLanguagesWhenAutoDetectWithoutDetectedDominantLanguageDoesNothing() {
        viewModel.setSourceLanguage(.auto)
        viewModel.setTargetLanguage(.indonesian)
        viewModel.detectedDominantLanguage = nil

        viewModel.swapLanguages()

        // Unchanged because source has no detected language to swap to
        XCTAssertEqual(viewModel.sourceLanguage, .auto)
        XCTAssertEqual(viewModel.targetLanguage, .indonesian)
    }

    // MARK: - 3. Block Selection & Detail Sheet Tests

    func testSelectBlockUpdatesSelectedBlockAndPresentsDetailSheet() {
        let block = TrackedTextBlock(
            rawLines: ["牛肉面"],
            mergedText: "牛肉面",
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            translatedText: "Mie Daging Sapi",
            sourceLanguage: "zh"
        )

        viewModel.selectBlock(block)

        XCTAssertEqual(viewModel.selectedBlock?.id, block.id)
        XCTAssertEqual(viewModel.selectedBlock?.mergedText, "牛肉面")
        XCTAssertTrue(viewModel.showDetailSheet)
    }

    func testSelectDetectedBlockConvenience() {
        let detected = DetectedTextBlock(
            rawLines: ["水饺"],
            mergedText: "水饺",
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            translatedText: "Pangsit Air"
        )

        viewModel.selectBlock(detected)

        XCTAssertEqual(viewModel.selectedBlock?.id, detected.id)
        XCTAssertEqual(viewModel.selectedBlock?.mergedText, "水饺")
        XCTAssertTrue(viewModel.showDetailSheet)
    }

    func testClearSelectionDismissesSheet() {
        let block = TrackedTextBlock(
            rawLines: ["牛肉面"],
            mergedText: "牛肉面",
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        )

        viewModel.selectBlock(block)
        XCTAssertTrue(viewModel.showDetailSheet)
        XCTAssertNotNil(viewModel.selectedBlock)

        viewModel.clearSelection()
        XCTAssertFalse(viewModel.showDetailSheet)
        XCTAssertNil(viewModel.selectedBlock)
    }

    // MARK: - 4. Torch & Freeze Frame Controls Tests

    func testToggleTorch() {
        XCTAssertFalse(viewModel.isTorchOn)

        viewModel.toggleTorch()
        XCTAssertTrue(viewModel.isTorchOn)
        XCTAssertEqual(mockTorch.torchMode, .on)

        viewModel.toggleTorch()
        XCTAssertFalse(viewModel.isTorchOn)
        XCTAssertEqual(mockTorch.torchMode, .off)
    }

    func testToggleFreezeFrame() {
        XCTAssertFalse(viewModel.isFrozen)

        viewModel.toggleFreeze()
        XCTAssertTrue(viewModel.isFrozen)
        XCTAssertTrue(cameraManager.isFrozen)

        viewModel.toggleFreeze()
        XCTAssertFalse(viewModel.isFrozen)
        XCTAssertFalse(cameraManager.isFrozen)
    }

    func testExplicitFreezeAndUnfreeze() {
        viewModel.freeze()
        XCTAssertTrue(viewModel.isFrozen)

        // Calling freeze again while already frozen is a no-op
        viewModel.freeze()
        XCTAssertTrue(viewModel.isFrozen)

        viewModel.unfreeze()
        XCTAssertFalse(viewModel.isFrozen)
    }

    func testClearTrackedBlocksResetsState() {
        let block = TrackedTextBlock(
            rawLines: ["牛肉面"],
            mergedText: "牛肉面",
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        )
        boxTracker.track(blocks: [block.toDetectedTextBlock()])
        viewModel.trackedBlocks = boxTracker.trackedBlocks
        viewModel.selectBlock(block)
        viewModel.errorMessage = "Some error"

        viewModel.clearTrackedBlocks()

        XCTAssertTrue(viewModel.trackedBlocks.isEmpty)
        XCTAssertNil(viewModel.selectedBlock)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(boxTracker.trackedBlocks.isEmpty)
    }

    // MARK: - 5. Frame Processing & Full Pipeline Orchestration Tests

    func testProcessFrameExecutesOCRTrackingAndTranslation() async throws {
        let detected = DetectedTextBlock(
            rawLines: ["红烧牛肉面"],
            mergedText: "红烧牛肉面",
            boundingBox: CGRect(x: 0.2, y: 0.5, width: 0.4, height: 0.1)
        )
        mockOCR.blocksToReturn = [detected]
        mockTranslation.mockTranslations = [
            "红烧牛肉面": "Mie Daging Sapi Semur"
        ]

        let pixelBuffer = createTestPixelBuffer()

        viewModel.processFrame(pixelBuffer)

        // Wait for async background task execution
        let expectation = XCTestExpectation(description: "Process frame and update tracked blocks with translation")
        
        Task {
            for _ in 0..<30 {
                if !self.viewModel.trackedBlocks.isEmpty &&
                   self.viewModel.trackedBlocks.first?.translatedText != nil {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(mockOCR.processCallCount, 1)
        XCTAssertEqual(mockTranslation.translateCallCount, 1)
        XCTAssertEqual(viewModel.trackedBlocks.count, 1)

        let first = try XCTUnwrap(viewModel.trackedBlocks.first)
        XCTAssertEqual(first.mergedText, "红烧牛肉面")
        XCTAssertEqual(first.translatedText, "Mie Daging Sapi Semur")

        // Dominant language should be detected as Chinese
        XCTAssertEqual(viewModel.detectedDominantLanguage?.bcp47Code, "zh-Hans")
    }

    func testProcessFrameDropsWhenFrozen() async {
        viewModel.freeze()
        XCTAssertTrue(viewModel.isFrozen)

        let pixelBuffer = createTestPixelBuffer()
        viewModel.processFrame(pixelBuffer)

        // Give any accidental tasks time to execute
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mockOCR.processCallCount, 0)
        XCTAssertTrue(viewModel.trackedBlocks.isEmpty)
    }

    func testProcessFrameDropsWhenThrottled() async {
        mockOCR.shouldThrottle = true

        let pixelBuffer = createTestPixelBuffer()
        viewModel.processFrame(pixelBuffer)

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mockOCR.processCallCount, 0)
        XCTAssertTrue(viewModel.trackedBlocks.isEmpty)
    }

    // MARK: - 6. Error Handling Tests

    func testOCRFailureSetsErrorMessage() async {
        mockOCR.shouldFail = true
        let pixelBuffer = createTestPixelBuffer()

        viewModel.processFrame(pixelBuffer)

        let expectation = XCTestExpectation(description: "Error message populated on OCR failure")

        Task {
            for _ in 0..<20 {
                if self.viewModel.errorMessage != nil {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: 1.5)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Simulated OCR failure") == true)
    }

    func testTranslationFailureSetsErrorMessage() async {
        let detected = DetectedTextBlock(
            rawLines: ["Halo Dunia"],
            mergedText: "Halo Dunia",
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
        )
        mockOCR.blocksToReturn = [detected]
        mockTranslation.shouldFail = true

        let pixelBuffer = createTestPixelBuffer()
        viewModel.processFrame(pixelBuffer)

        let expectation = XCTestExpectation(description: "Error message populated on translation failure")

        Task {
            for _ in 0..<20 {
                if self.viewModel.errorMessage != nil {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: 1.5)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Simulated Translation failure") == true)
    }

    // MARK: - 7. Retranslate All on Language Change

    func testRetranslateAllClearsAndRefreshesTranslations() async {
        let block = TrackedTextBlock(
            rawLines: ["Welcome"],
            mergedText: "Welcome",
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
            translatedText: "Selamat Datang"
        )
        boxTracker.track(blocks: [block.toDetectedTextBlock()])
        viewModel.trackedBlocks = boxTracker.trackedBlocks

        mockTranslation.mockTranslations = [
            "Welcome": "Bienvenue"
        ]

        viewModel.setTargetLanguage(.french)

        let expectation = XCTestExpectation(description: "Refreshes translation with new target language")

        Task {
            for _ in 0..<20 {
                if self.viewModel.trackedBlocks.first?.translatedText == "Bienvenue" {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: 1.5)

        XCTAssertEqual(viewModel.trackedBlocks.first?.translatedText, "Bienvenue")
    }

    // MARK: - 8. Language Persistence Tests

    func testLanguagePreferencesPersistenceInUserDefaults() {
        let suiteName = "test.camera.vm.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let vm = CameraTranslationViewModel(
            cameraManager: cameraManager,
            ocrService: mockOCR,
            translationService: mockTranslation,
            languageDetectionService: languageDetector,
            boxTracker: boxTracker,
            userDefaults: defaults
        )

        // Set languages -> should write to UserDefaults
        vm.setSourceLanguage(.japanese)
        vm.setTargetLanguage(.french)

        XCTAssertEqual(defaults.string(forKey: CameraTranslationViewModel.sourceLanguageDefaultsKey), "ja")
        XCTAssertEqual(defaults.string(forKey: CameraTranslationViewModel.targetLanguageDefaultsKey), "fr")

        // Initialize a new ViewModel with the same UserDefaults instance -> should restore saved preferences
        let restoredVM = CameraTranslationViewModel(
            cameraManager: cameraManager,
            ocrService: mockOCR,
            translationService: mockTranslation,
            languageDetectionService: languageDetector,
            boxTracker: boxTracker,
            userDefaults: defaults
        )

        XCTAssertEqual(restoredVM.sourceLanguage, .japanese)
        XCTAssertEqual(restoredVM.targetLanguage, .french)
    }

    func testSwapLanguagesUpdatesUserDefaults() {
        let suiteName = "test.camera.vm.swap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let vm = CameraTranslationViewModel(
            cameraManager: cameraManager,
            ocrService: mockOCR,
            translationService: mockTranslation,
            languageDetectionService: languageDetector,
            boxTracker: boxTracker,
            userDefaults: defaults
        )

        vm.setSourceLanguage(.german)
        vm.setTargetLanguage(.italian)

        vm.swapLanguages()

        XCTAssertEqual(defaults.string(forKey: CameraTranslationViewModel.sourceLanguageDefaultsKey), "it")
        XCTAssertEqual(defaults.string(forKey: CameraTranslationViewModel.targetLanguageDefaultsKey), "de")
        XCTAssertEqual(vm.sourceLanguage, .italian)
        XCTAssertEqual(vm.targetLanguage, .german)
    }
}
