import XCTest
import CoreGraphics
import CoreVideo
import ImageIO
import Vision
@testable import RealtimeTranslateApp

// MARK: - Mock Vision Text Recognizer

final class MockVisionTextRecognizer: VisionTextRecognizerProtocol, @unchecked Sendable {
    var stubbedLines: [OCRLine] = []
    var shouldFail: Bool = false
    var failureMessage: String = "Simulated recognition failure"
    var lastOrientation: CGImagePropertyOrientation?
    var lastConfiguration: OCRConfiguration?
    var callCount: Int = 0

    func recognizeText(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        configuration: OCRConfiguration
    ) throws -> [OCRLine] {
        callCount += 1
        lastOrientation = orientation
        lastConfiguration = configuration

        if shouldFail {
            throw OCRError.recognitionFailed(failureMessage)
        }
        return stubbedLines
    }

    func recognizeText(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        configuration: OCRConfiguration
    ) throws -> [OCRLine] {
        callCount += 1
        lastOrientation = orientation
        lastConfiguration = configuration

        if shouldFail {
            throw OCRError.recognitionFailed(failureMessage)
        }
        return stubbedLines
    }
}

// MARK: - Test Helpers

private func createDummyPixelBuffer(width: Int = 32, height: Int = 32) -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        attributes as CFDictionary,
        &pixelBuffer
    )
    assert(status == kCVReturnSuccess && pixelBuffer != nil, "Failed to create dummy pixel buffer")
    return pixelBuffer!
}

private func createDummyCGImage(width: Int = 32, height: Int = 32) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return context!.makeImage()!
}

// MARK: - OCRServiceTests

final class OCRServiceTests: XCTestCase {

    // MARK: - 1. Configuration Tests

    func testDefaultConfigurationParameters() {
        let config = OCRConfiguration.default

        XCTAssertEqual(config.recognitionLevel, .accurate)
        XCTAssertTrue(config.usesLanguageCorrection)
        XCTAssertTrue(config.automaticallyDetectsLanguage)
        XCTAssertEqual(config.minimumConfidence, 0.3)
        XCTAssertEqual(config.lineSpacingThreshold, 0.04)
        XCTAssertEqual(config.minimumFrameInterval, 0.15)

        // Verify key languages are present
        XCTAssertTrue(config.recognitionLanguages.contains("zh-Hans"))
        XCTAssertTrue(config.recognitionLanguages.contains("zh-Hant"))
        XCTAssertTrue(config.recognitionLanguages.contains("en-US"))
        XCTAssertTrue(config.recognitionLanguages.contains("id-ID"))
        XCTAssertTrue(config.recognitionLanguages.contains("ja-JP"))
        XCTAssertTrue(config.recognitionLanguages.contains("ko-KR"))
    }

    func testCustomConfigurationParameters() {
        let customLanguages = ["fr-FR", "de-DE"]
        let customConfig = OCRConfiguration(
            recognitionLevel: .fast,
            usesLanguageCorrection: false,
            recognitionLanguages: customLanguages,
            automaticallyDetectsLanguage: false,
            minimumConfidence: 0.75,
            minimumTextHeight: 0.05,
            lineSpacingThreshold: 0.08,
            minimumFrameInterval: 0.25
        )

        let service = OCRService(configuration: customConfig)

        XCTAssertEqual(service.configuration.recognitionLevel, .fast)
        XCTAssertFalse(service.configuration.usesLanguageCorrection)
        XCTAssertEqual(service.configuration.recognitionLanguages, customLanguages)
        XCTAssertFalse(service.configuration.automaticallyDetectsLanguage)
        XCTAssertEqual(service.configuration.minimumConfidence, 0.75)
        XCTAssertEqual(service.configuration.minimumTextHeight, 0.05)
        XCTAssertEqual(service.configuration.lineSpacingThreshold, 0.08)
        XCTAssertEqual(service.configuration.minimumFrameInterval, 0.25)
    }

    // MARK: - 2. Frame Throttling Tests

    func testFrameThrottlerInitialStateAllowsFrame() {
        let throttler = FrameThrottler(minimumInterval: 0.15)

        XCTAssertFalse(throttler.isProcessing)
        XCTAssertNil(throttler.lastProcessedDate)
        XCTAssertTrue(throttler.shouldProcessFrame())
    }

    func testFrameThrottlerDropsFramesWhileBusy() {
        let throttler = FrameThrottler(minimumInterval: 0.15)

        // Acquire frame -> marks busy
        let acquired = throttler.acquireFrame()
        XCTAssertTrue(acquired)
        XCTAssertTrue(throttler.isProcessing)

        // Subsequent checks while busy must return false
        XCTAssertFalse(throttler.shouldProcessFrame())
        XCTAssertFalse(throttler.acquireFrame())

        // Releasing frame resets isProcessing
        throttler.releaseFrame()
        XCTAssertFalse(throttler.isProcessing)
    }

    func testFrameThrottlerEnforcesMinimumTimeInterval() {
        let throttler = FrameThrottler(minimumInterval: 0.15)
        let baseDate = Date(timeIntervalSince1970: 1000.0)

        // Frame 1 at t = 0s
        XCTAssertTrue(throttler.acquireFrame(at: baseDate))
        throttler.releaseFrame()

        // Frame 2 at t = +0.05s (50ms < 150ms interval) -> must drop
        let dateAfter50ms = baseDate.addingTimeInterval(0.05)
        XCTAssertFalse(throttler.shouldProcessFrame(at: dateAfter50ms))
        XCTAssertFalse(throttler.acquireFrame(at: dateAfter50ms))

        // Frame 3 at t = +0.10s (100ms < 150ms interval) -> must drop
        let dateAfter100ms = baseDate.addingTimeInterval(0.10)
        XCTAssertFalse(throttler.shouldProcessFrame(at: dateAfter100ms))
        XCTAssertFalse(throttler.acquireFrame(at: dateAfter100ms))

        // Frame 4 at t = +0.15s (150ms == 150ms interval) -> must allow
        let dateAfter150ms = baseDate.addingTimeInterval(0.15)
        XCTAssertTrue(throttler.shouldProcessFrame(at: dateAfter150ms))
        XCTAssertTrue(throttler.acquireFrame(at: dateAfter150ms))
    }

    func testFrameThrottlerResetRestoresReadyState() {
        let throttler = FrameThrottler(minimumInterval: 0.15)
        let date = Date()
        _ = throttler.acquireFrame(at: date)
        XCTAssertTrue(throttler.isProcessing)
        XCTAssertNotNil(throttler.lastProcessedDate)

        throttler.reset()

        XCTAssertFalse(throttler.isProcessing)
        XCTAssertNil(throttler.lastProcessedDate)
        XCTAssertTrue(throttler.shouldProcessFrame())
    }

    // MARK: - 3. OCR Service Throttling Integration Tests

    func testOCRServiceDropsFrameWhenThrottled() async {
        let mockRecognizer = MockVisionTextRecognizer()
        let throttler = FrameThrottler(minimumInterval: 0.15)
        let service = OCRService(throttler: throttler, recognizer: mockRecognizer)

        let pixelBuffer = createDummyPixelBuffer()

        // Simulate frame acquisition in-flight
        _ = throttler.acquireFrame()

        do {
            _ = try await service.process(pixelBuffer: pixelBuffer)
            XCTFail("Expected OCRError.frameThrottled to be thrown")
        } catch let error as OCRError {
            XCTAssertEqual(error, .frameThrottled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(mockRecognizer.callCount, 0, "Recognizer should not be called when frame is throttled")
    }

    func testOCRServiceBypassesThrottlingWhenExplicitlyRequested() async throws {
        let mockRecognizer = MockVisionTextRecognizer()
        mockRecognizer.stubbedLines = [
            OCRLine(text: "Frozen Frame", boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.05))
        ]
        let throttler = FrameThrottler(minimumInterval: 0.15)
        let service = OCRService(throttler: throttler, recognizer: mockRecognizer)

        let pixelBuffer = createDummyPixelBuffer()

        // Mark throttler busy
        _ = throttler.acquireFrame()

        // Calling with ignoreThrottling: true must bypass the check
        let blocks = try await service.process(pixelBuffer: pixelBuffer, ignoreThrottling: true)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "Frozen Frame")
        XCTAssertEqual(mockRecognizer.callCount, 1)
    }

    // MARK: - 4. Spatial Clustering Integration Tests

    func testOCRServiceSpatialClusteringIntegration() async throws {
        let mockRecognizer = MockVisionTextRecognizer()
        mockRecognizer.stubbedLines = [
            OCRLine(text: "红烧", boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.2, height: 0.05)),
            OCRLine(text: "牛肉面", boundingBox: CGRect(x: 0.1, y: 0.74, width: 0.25, height: 0.05))
        ]

        let throttler = FrameThrottler(minimumInterval: 0.0) // No throttling delay for this test
        let service = OCRService(throttler: throttler, recognizer: mockRecognizer)

        let pixelBuffer = createDummyPixelBuffer()
        let blocks = try await service.process(pixelBuffer: pixelBuffer)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "红烧牛肉面")
        XCTAssertEqual(blocks.first?.rawLines, ["红烧", "牛肉面"])
        XCTAssertEqual(blocks.first?.boundingBox.minX, 0.1)
        XCTAssertEqual(blocks.first?.boundingBox.minY, 0.74)
        XCTAssertEqual(blocks.first?.boundingBox.maxY, 0.85)
    }

    func testOCRServiceDistantLinesProduceMultipleBlocks() async throws {
        let mockRecognizer = MockVisionTextRecognizer()
        mockRecognizer.stubbedLines = [
            OCRLine(text: "Header Title", boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.4, height: 0.05)),
            OCRLine(text: "Footer Note", boundingBox: CGRect(x: 0.1, y: 0.10, width: 0.4, height: 0.05))
        ]

        let throttler = FrameThrottler(minimumInterval: 0.0)
        let service = OCRService(throttler: throttler, recognizer: mockRecognizer)

        let cgImage = createDummyCGImage()
        let blocks = try await service.process(cgImage: cgImage)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].mergedText, "Header Title")
        XCTAssertEqual(blocks[1].mergedText, "Footer Note")
    }

    func testOCRServicePropagatesRecognizerFailureAndReleasesLock() async {
        let mockRecognizer = MockVisionTextRecognizer()
        mockRecognizer.shouldFail = true
        mockRecognizer.failureMessage = "Neural engine timeout"

        let throttler = FrameThrottler(minimumInterval: 0.0)
        let service = OCRService(throttler: throttler, recognizer: mockRecognizer)

        let pixelBuffer = createDummyPixelBuffer()

        do {
            _ = try await service.process(pixelBuffer: pixelBuffer)
            XCTFail("Expected failure to be thrown")
        } catch let error as OCRError {
            XCTAssertEqual(error, .recognitionFailed("Neural engine timeout"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Verify throttler busy lock was released in defer block
        XCTAssertFalse(throttler.isProcessing)
    }

    func testOCRServiceEmptyRecognitionReturnsEmptyArray() async throws {
        let mockRecognizer = MockVisionTextRecognizer()
        mockRecognizer.stubbedLines = []

        let throttler = FrameThrottler(minimumInterval: 0.0)
        let service = OCRService(throttler: throttler, recognizer: mockRecognizer)

        let pixelBuffer = createDummyPixelBuffer()
        let blocks = try await service.process(pixelBuffer: pixelBuffer)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testOCRServiceClusterHelperDirect() {
        let service = OCRService()
        let lines = [
            OCRLine(text: "Nasi", boundingBox: CGRect(x: 0.2, y: 0.60, width: 0.2, height: 0.04)),
            OCRLine(text: "Goreng", boundingBox: CGRect(x: 0.2, y: 0.55, width: 0.25, height: 0.04))
        ]

        let blocks = service.cluster(lines: lines)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "Nasi Goreng")
    }

    func testOCRErrorDescriptions() {
        let throttled = OCRError.frameThrottled
        let failed = OCRError.recognitionFailed("Timeout")
        let invalid = OCRError.invalidInput
        let cancelled = OCRError.cancelled

        XCTAssertNotNil(throttled.errorDescription)
        XCTAssertTrue(failed.errorDescription?.contains("Timeout") == true)
        XCTAssertNotNil(invalid.errorDescription)
        XCTAssertNotNil(cancelled.errorDescription)
    }
}
