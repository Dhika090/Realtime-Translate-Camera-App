import XCTest
import CoreGraphics
@testable import RealtimeTranslateApp

final class CoordinateTransformerTests: XCTestCase {

    // MARK: - Vision to Screen Coordinate Conversion Tests

    /// Tests conversion when the view aspect ratio exactly matches the video aspect ratio (no aspect-fill crop).
    func testVisionToScreenCoordinateConversionMatchingAspect() {
        // Given a normalized Vision rect (origin bottom-left, Y-up)
        // y: 0.8, height: 0.1 -> top edge in Vision is 0.9.
        // In screen coordinates (origin top-left, Y-down), top edge should be 1.0 - 0.9 = 0.1.
        let visionRect = CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1)
        let viewSize = CGSize(width: 400, height: 800)
        let videoAspectRatio: CGFloat = 400.0 / 800.0 // 0.5 (matches view)

        let screenRect = CoordinateTransformer.convert(
            visionRect: visionRect,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        )

        XCTAssertEqual(screenRect.origin.x, 40, accuracy: 0.001)
        XCTAssertEqual(screenRect.origin.y, 80, accuracy: 0.001) // (1.0 - 0.8 - 0.1) * 800 = 80
        XCTAssertEqual(screenRect.width, 120, accuracy: 0.001)
        XCTAssertEqual(screenRect.height, 80, accuracy: 0.001)
    }

    /// Tests conversion on an iPhone screen that is narrower/taller than 16:9 video (e.g., modern notch/island iPhones).
    /// With `.resizeAspectFill`, video height fills view height and video width is cropped symmetrically on left and right.
    func testVisionToScreenCoordinateConversionAspectFillTallerScreen() {
        let videoAspectRatio: CGFloat = 9.0 / 16.0 // 0.5625
        let viewSize = CGSize(width: 360, height: 800) // View ratio: 360 / 800 = 0.45 < 0.5625

        // Scaled height: 800
        // Scaled width: 800 * (9/16) = 450
        // Offset X: (360 - 450) / 2 = -45 (cropped by 45 points on left and right)
        // Offset Y: 0

        // Center box in Vision: [0.4, 0.4, 0.2, 0.2]
        let centerVisionRect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let screenRect = CoordinateTransformer.convert(
            visionRect: centerVisionRect,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        )

        // Screen X: -45 + (0.4 * 450) = -45 + 180 = 135
        // Screen Width: 0.2 * 450 = 90
        // Screen Center X: 135 + 45 = 180 (exact horizontal midpoint of 360 view)
        XCTAssertEqual(screenRect.origin.x, 135, accuracy: 0.001)
        XCTAssertEqual(screenRect.width, 90, accuracy: 0.001)
        XCTAssertEqual(screenRect.midX, 180, accuracy: 0.001)

        // Screen Y: 0 + ((1.0 - 0.4 - 0.2) * 800) = 0.4 * 800 = 320
        // Screen Height: 0.2 * 800 = 160
        // Screen Center Y: 320 + 80 = 400 (exact vertical midpoint of 800 view)
        XCTAssertEqual(screenRect.origin.y, 320, accuracy: 0.001)
        XCTAssertEqual(screenRect.height, 160, accuracy: 0.001)
        XCTAssertEqual(screenRect.midY, 400, accuracy: 0.001)
    }

    /// Tests conversion on a display wider than 16:9 video (e.g., iPad or landscape orientation).
    /// With `.resizeAspectFill`, video width fills view width and video height is cropped symmetrically on top and bottom.
    func testVisionToScreenCoordinateConversionAspectFillWiderScreen() {
        let videoAspectRatio: CGFloat = 9.0 / 16.0 // 0.5625
        let viewSize = CGSize(width: 600, height: 800) // View ratio: 600 / 800 = 0.75 > 0.5625

        // Scaled width: 600
        // Scaled height: 600 / (9/16) = 1066.6667
        // Offset X: 0
        // Offset Y: (800 - 1066.6667) / 2 = -133.3333

        // Center box in Vision: [0.4, 0.4, 0.2, 0.2]
        let centerVisionRect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let screenRect = CoordinateTransformer.convert(
            visionRect: centerVisionRect,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        )

        // Screen X: 0 + 0.4 * 600 = 240
        // Screen Width: 0.2 * 600 = 120
        // Screen Center X: 240 + 60 = 300 (midpoint of 600)
        XCTAssertEqual(screenRect.origin.x, 240, accuracy: 0.001)
        XCTAssertEqual(screenRect.width, 120, accuracy: 0.001)
        XCTAssertEqual(screenRect.midX, 300, accuracy: 0.001)

        // Screen Center Y: midpoint of 800
        XCTAssertEqual(screenRect.midY, 400, accuracy: 0.001)
    }

    /// Tests degenerate cases such as zero view size.
    func testVisionToScreenDegenerateCases() {
        let visionRect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)

        let zeroWidth = CoordinateTransformer.convert(
            visionRect: visionRect,
            viewSize: CGSize(width: 0, height: 800)
        )
        XCTAssertEqual(zeroWidth, .zero)

        let zeroHeight = CoordinateTransformer.convert(
            visionRect: visionRect,
            viewSize: CGSize(width: 400, height: 0)
        )
        XCTAssertEqual(zeroHeight, .zero)
    }

    // MARK: - Screen to Vision Round-Trip Inversion Tests

    /// Tests that converting a Vision rect to screen coordinates and back to Vision coordinates yields the original rect.
    func testRoundTripVisionToScreenAndBack() {
        let originalVisionRect = CGRect(x: 0.25, y: 0.35, width: 0.40, height: 0.15)
        let viewSize = CGSize(width: 393, height: 852) // iPhone 15 Pro dimensions
        let videoAspectRatio: CGFloat = 9.0 / 16.0

        let screenRect = CoordinateTransformer.convert(
            visionRect: originalVisionRect,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        )

        let reconstructedVisionRect = CoordinateTransformer.convertToVision(
            screenRect: screenRect,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        )

        XCTAssertEqual(reconstructedVisionRect.origin.x, originalVisionRect.origin.x, accuracy: 0.0001)
        XCTAssertEqual(reconstructedVisionRect.origin.y, originalVisionRect.origin.y, accuracy: 0.0001)
        XCTAssertEqual(reconstructedVisionRect.width, originalVisionRect.width, accuracy: 0.0001)
        XCTAssertEqual(reconstructedVisionRect.height, originalVisionRect.height, accuracy: 0.0001)
    }

    /// Tests point conversion round-trip.
    func testPointConversionRoundTrip() {
        let originalPoint = CGPoint(x: 0.72, y: 0.43)
        let viewSize = CGSize(width: 393, height: 852)
        let videoAspectRatio: CGFloat = 9.0 / 16.0

        let screenPoint = CoordinateTransformer.convert(
            visionPoint: originalPoint,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        )

        let reconstructedPoint = CoordinateTransformer.convertToVision(
            screenPoint: screenPoint,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        )

        XCTAssertEqual(reconstructedPoint.x, originalPoint.x, accuracy: 0.0001)
        XCTAssertEqual(reconstructedPoint.y, originalPoint.y, accuracy: 0.0001)
    }

    // MARK: - Exponential Moving Average (EMA) Smoothing Tests

    /// Tests standard EMA smoothing formula: `new_val = current + (target - current) * factor`.
    func testEMASmoothingStep() {
        let current = CGRect(x: 100, y: 100, width: 200, height: 50)
        let target = CGRect(x: 120, y: 110, width: 210, height: 60)
        let factor: CGFloat = 0.4

        let smoothed = CoordinateTransformer.smooth(current: current, target: target, factor: factor)

        // expectedX = 100 + (120 - 100) * 0.4 = 108
        // expectedY = 100 + (110 - 100) * 0.4 = 104
        // expectedW = 200 + (210 - 200) * 0.4 = 204
        // expectedH = 50 + (60 - 50) * 0.4 = 54
        XCTAssertEqual(smoothed.origin.x, 108, accuracy: 0.001)
        XCTAssertEqual(smoothed.origin.y, 104, accuracy: 0.001)
        XCTAssertEqual(smoothed.width, 204, accuracy: 0.001)
        XCTAssertEqual(smoothed.height, 54, accuracy: 0.001)
    }

    /// Tests that negligible differences (< 1 pixel) snap directly to target to eliminate subpixel micro-jitter.
    func testEMASmoothingNegligibleThresholdSnap() {
        let current = CGRect(x: 100.0, y: 200.0, width: 150.0, height: 40.0)
        let target = CGRect(x: 100.4, y: 200.3, width: 150.2, height: 40.5) // All deltas < 1.0 point

        let smoothed = CoordinateTransformer.smooth(
            current: current,
            target: target,
            factor: 0.35,
            pixelSnapThreshold: 1.0
        )

        XCTAssertEqual(smoothed, target)
    }

    /// Tests that very large differences (camera sweep or scene change) snap directly to target to avoid ghost lagging.
    func testEMASmoothingLargeJumpSnap() {
        let current = CGRect(x: 50, y: 50, width: 100, height: 30)
        let target = CGRect(x: 350, y: 400, width: 100, height: 30) // distance > 150 points

        let smoothed = CoordinateTransformer.smooth(
            current: current,
            target: target,
            factor: 0.35,
            snapThreshold: 150.0
        )

        XCTAssertEqual(smoothed, target)
    }

    /// Tests that EMA smoothing adapts properly to normalized coordinates (0...1).
    func testEMASmoothingNormalizedCoordinates() {
        let current = CGRect(x: 0.20, y: 0.40, width: 0.30, height: 0.05)
        let target = CGRect(x: 0.22, y: 0.42, width: 0.30, height: 0.05)
        let factor: CGFloat = 0.5

        let smoothed = CoordinateTransformer.smooth(current: current, target: target, factor: factor)

        // expectedX = 0.20 + (0.22 - 0.20) * 0.5 = 0.21
        // expectedY = 0.40 + (0.42 - 0.40) * 0.5 = 0.41
        XCTAssertEqual(smoothed.origin.x, 0.21, accuracy: 0.0001)
        XCTAssertEqual(smoothed.origin.y, 0.41, accuracy: 0.0001)
    }

    /// Tests boundary factors (factor <= 0 returns current, factor >= 1 returns target).
    func testEMASmoothingBoundaryFactors() {
        let current = CGRect(x: 10, y: 20, width: 100, height: 30)
        let target = CGRect(x: 50, y: 60, width: 120, height: 40)

        let factorZero = CoordinateTransformer.smooth(current: current, target: target, factor: 0.0)
        XCTAssertEqual(factorZero, current)

        let factorOne = CoordinateTransformer.smooth(current: current, target: target, factor: 1.0)
        XCTAssertEqual(factorOne, target)
    }

    // MARK: - Intersection over Union (IoU) Tests

    /// Tests IoU between identical rectangles evaluates to 1.0.
    func testIntersectionOverUnionIdenticalRects() {
        let rect = CGRect(x: 100, y: 150, width: 200, height: 50)
        let score = CoordinateTransformer.intersectionOverUnion(rect, rect)
        XCTAssertEqual(score, 1.0, accuracy: 0.0001)
    }

    /// Tests IoU between disjoint rectangles evaluates to 0.0.
    func testIntersectionOverUnionDisjointRects() {
        let rect1 = CGRect(x: 0, y: 0, width: 50, height: 50)
        let rect2 = CGRect(x: 100, y: 100, width: 50, height: 50)
        let score = CoordinateTransformer.intersectionOverUnion(rect1, rect2)
        XCTAssertEqual(score, 0.0, accuracy: 0.0001)
    }

    /// Tests IoU on partially overlapping rectangles with known ground truth area.
    func testIntersectionOverUnionPartialOverlap() {
        // rect1: [0, 0, 100, 100] -> Area = 10,000
        // rect2: [50, 0, 100, 100] -> Area = 10,000
        // Intersection: [50, 0, 50, 100] -> Area = 5,000
        // Union: 10,000 + 10,000 - 5,000 = 15,000
        // IoU: 5,000 / 15,000 = 1/3 ≈ 0.33333
        let rect1 = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect2 = CGRect(x: 50, y: 0, width: 100, height: 100)

        let score = CoordinateTransformer.intersectionOverUnion(rect1, rect2)
        XCTAssertEqual(score, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(CoordinateTransformer.iou(rect1, rect2), 1.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - BoxTracker Multi-Frame Temporal Tracking Tests

    /// Tests that consecutive frames with overlapping bounding boxes (IoU >= 0.35) preserve the stable block ID.
    func testBoxTrackerPreservesBlockIdentityAndSmoothsBox() {
        let tracker = BoxTracker(iouThreshold: 0.35, smoothingFactor: 0.5)

        // Frame 1: Detection at (100, 100, 200, 50)
        let originalId = UUID()
        let blockFrame1 = DetectedTextBlock(
            id: originalId,
            rawLines: ["Hello World"],
            mergedText: "Hello World",
            boundingBox: CGRect(x: 100, y: 100, width: 200, height: 50)
        )

        let tracked1 = tracker.track(blocks: [blockFrame1])
        XCTAssertEqual(tracked1.count, 1)
        XCTAssertEqual(tracked1.first?.id, originalId)
        XCTAssertEqual(tracked1.first?.boundingBox, CGRect(x: 100, y: 100, width: 200, height: 50))

        // Frame 2: Same text slightly shifted to (106, 104, 200, 50) (high IoU > 0.8)
        let newDetectionId = UUID() // OCR generated a new temporary ID
        let blockFrame2 = DetectedTextBlock(
            id: newDetectionId,
            rawLines: ["Hello World"],
            mergedText: "Hello World",
            boundingBox: CGRect(x: 106, y: 104, width: 200, height: 50)
        )

        let tracked2 = tracker.track(blocks: [blockFrame2])
        XCTAssertEqual(tracked2.count, 1)

        // Verifies stable identity is preserved from Frame 1, NOT replaced by Frame 2's temporary UUID
        XCTAssertEqual(tracked2.first?.id, originalId)

        // Verifies coordinate smoothing with factor 0.5:
        // x: 100 + (106 - 100) * 0.5 = 103
        // y: 100 + (104 - 100) * 0.5 = 102
        XCTAssertEqual(tracked2.first?.boundingBox.origin.x, 103, accuracy: 0.001)
        XCTAssertEqual(tracked2.first?.boundingBox.origin.y, 102, accuracy: 0.001)
    }

    /// Tests that existing translation results are retained across frames even when subsequent OCR detections lack translation.
    func testBoxTrackerRetainsExistingTranslatedText() {
        let tracker = BoxTracker(iouThreshold: 0.35)

        // Frame 1: Block with translation completed
        let blockFrame1 = DetectedTextBlock(
            rawLines: ["牛肉面"],
            mergedText: "牛肉面",
            boundingBox: CGRect(x: 100, y: 100, width: 120, height: 40),
            translatedText: "Mie Sapi",
            sourceLanguage: "zh"
        )
        tracker.track(blocks: [blockFrame1])

        // Frame 2: Fast OCR frame arrives with no translation yet
        let blockFrame2 = DetectedTextBlock(
            rawLines: ["牛肉面"],
            mergedText: "牛肉面",
            boundingBox: CGRect(x: 102, y: 101, width: 120, height: 40),
            translatedText: nil, // Not translated in this frame
            sourceLanguage: nil
        )
        let tracked = tracker.track(blocks: [blockFrame2])

        XCTAssertEqual(tracked.count, 1)
        // Translation and source language must be retained from Frame 1
        XCTAssertEqual(tracked.first?.translatedText, "Mie Sapi")
        XCTAssertEqual(tracked.first?.sourceLanguage, "zh")
    }

    /// Tests that unobserved blocks are retained for `maxMissedFrames` and pruned once that threshold is exceeded.
    func testBoxTrackerPrunesStaleBlocksAfterMaxMissedFrames() {
        let maxMissed = 3
        let tracker = BoxTracker(maxMissedFrames: maxMissed)

        let block = DetectedTextBlock(
            rawLines: ["Target Text"],
            mergedText: "Target Text",
            boundingBox: CGRect(x: 50, y: 50, width: 100, height: 30)
        )

        // Frame 1: Detected
        var tracked = tracker.track(blocks: [block])
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.missedFrames, 0)

        // Frame 2: Missed 1 frame (retained)
        tracked = tracker.track(blocks: [])
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.missedFrames, 1)

        // Frame 3: Missed 2 frames (retained)
        tracked = tracker.track(blocks: [])
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.missedFrames, 2)

        // Frame 4: Missed 3 frames (retained, at limit)
        tracked = tracker.track(blocks: [])
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked.first?.missedFrames, 3)

        // Frame 5: Missed 4 frames (> maxMissed 3 -> pruned)
        tracked = tracker.track(blocks: [])
        XCTAssertTrue(tracked.isEmpty, "Block must be pruned after exceeding maxMissedFrames")
    }

    /// Tests that when a block is re-detected before reaching maxMissedFrames, missedFrames resets to 0.
    func testBoxTrackerResetsMissedFramesUponRedetection() {
        let tracker = BoxTracker(iouThreshold: 0.35, maxMissedFrames: 3)

        let initialBlock = DetectedTextBlock(
            rawLines: ["Special"],
            mergedText: "Special",
            boundingBox: CGRect(x: 100, y: 100, width: 80, height: 30)
        )
        let initialTracked = tracker.track(blocks: [initialBlock])
        let stableId = initialTracked[0].id

        // Missed for 2 frames
        _ = tracker.track(blocks: [])
        _ = tracker.track(blocks: [])
        XCTAssertEqual(tracker.trackedBlocks.first?.missedFrames, 2)

        // Frame 4: Re-detected at similar location
        let redetectedBlock = DetectedTextBlock(
            rawLines: ["Special"],
            mergedText: "Special",
            boundingBox: CGRect(x: 102, y: 101, width: 80, height: 30)
        )
        let result = tracker.track(blocks: [redetectedBlock])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, stableId)
        XCTAssertEqual(result.first?.missedFrames, 0)
    }

    /// Tests that non-overlapping blocks are introduced as distinct new blocks.
    func testBoxTrackerIntroducesNewBlocksWhenIoUBelowThreshold() {
        let tracker = BoxTracker(iouThreshold: 0.35)

        let blockA = DetectedTextBlock(
            rawLines: ["Header"],
            mergedText: "Header",
            boundingBox: CGRect(x: 20, y: 20, width: 100, height: 30)
        )
        let tracked1 = tracker.track(blocks: [blockA])
        XCTAssertEqual(tracked1.count, 1)

        // Frame 2: Block B detected far away from Block A (disjoint)
        let blockB = DetectedTextBlock(
            rawLines: ["Footer"],
            mergedText: "Footer",
            boundingBox: CGRect(x: 20, y: 500, width: 100, height: 30)
        )
        let tracked2 = tracker.track(blocks: [blockB])

        // Tracker now holds both: Block A (missed 1 frame) and Block B (newly detected)
        XCTAssertEqual(tracked2.count, 2)

        let texts = tracked2.map { $0.mergedText }
        XCTAssertTrue(texts.contains("Header"))
        XCTAssertTrue(texts.contains("Footer"))
    }

    /// Tests end-to-end tracking pipeline converting from Vision normalized coordinates directly to screen space.
    func testBoxTrackerVisionConversionPipeline() {
        let tracker = BoxTracker()
        let viewSize = CGSize(width: 360, height: 640) // 9:16 aspect ratio

        // Vision normalized box at bottom-left corner: (0.1, 0.8, 0.3, 0.1)
        let visionBlock = DetectedTextBlock(
            rawLines: ["Vision Pipeline"],
            mergedText: "Vision Pipeline",
            boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1)
        )

        let tracked = tracker.track(
            visionBlocks: [visionBlock],
            viewSize: viewSize,
            videoAspectRatio: 9.0 / 16.0
        )

        XCTAssertEqual(tracked.count, 1)
        let screenBox = tracked[0].boundingBox

        // In screen coordinates:
        // x = 0.1 * 360 = 36
        // y = (1.0 - 0.8 - 0.1) * 640 = 64
        // width = 0.3 * 360 = 108
        // height = 0.1 * 640 = 64
        XCTAssertEqual(screenBox.origin.x, 36, accuracy: 0.001)
        XCTAssertEqual(screenBox.origin.y, 64, accuracy: 0.001)
        XCTAssertEqual(screenBox.width, 108, accuracy: 0.001)
        XCTAssertEqual(screenBox.height, 64, accuracy: 0.001)
    }

    /// Tests asynchronous translation updates for an active tracked block.
    func testBoxTrackerAsyncTranslationUpdate() {
        let tracker = BoxTracker()
        let block = DetectedTextBlock(
            rawLines: ["Bonjour"],
            mergedText: "Bonjour",
            boundingBox: CGRect(x: 50, y: 50, width: 80, height: 30)
        )
        let tracked = tracker.track(blocks: [block])
        let blockId = tracked[0].id

        XCTAssertNil(tracker.trackedBlocks.first?.translatedText)

        let success = tracker.updateTranslation(
            for: blockId,
            translatedText: "Halo",
            sourceLanguage: "fr"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(tracker.trackedBlocks.first?.translatedText, "Halo")
        XCTAssertEqual(tracker.trackedBlocks.first?.sourceLanguage, "fr")

        // Updating a nonexistent ID returns false
        let fakeSuccess = tracker.updateTranslation(for: UUID(), translatedText: "Test")
        XCTAssertFalse(fakeSuccess)
    }

    /// Tests tracker reset functionality.
    func testBoxTrackerReset() {
        let tracker = BoxTracker()
        let block = DetectedTextBlock(
            rawLines: ["Test"],
            mergedText: "Test",
            boundingBox: CGRect(x: 10, y: 10, width: 50, height: 20)
        )
        tracker.track(blocks: [block])
        XCTAssertFalse(tracker.trackedBlocks.isEmpty)

        tracker.reset()
        XCTAssertTrue(tracker.trackedBlocks.isEmpty)
        XCTAssertTrue(tracker.currentBlocks.isEmpty)
        XCTAssertTrue(tracker.activeDetectedBlocks.isEmpty)
    }
}
