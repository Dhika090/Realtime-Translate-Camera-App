import Foundation
import CoreGraphics

// MARK: - Coordinate Transformer

/// Utility for converting between Vision normalized coordinate space and SwiftUI / UIKit view coordinates,
/// as well as calculating bounding box smoothing and overlap metrics.
///
/// Vision Framework Coordinate System:
/// - Origin `(0, 0)` is at the **bottom-left** corner.
/// - `X` increases rightward from `0.0` to `1.0`.
/// - `Y` increases upward from `0.0` to `1.0`.
///
/// SwiftUI / UIKit Screen Coordinate System:
/// - Origin `(0, 0)` is at the **top-left** corner.
/// - `X` increases rightward from `0.0` to `viewWidth`.
/// - `Y` increases downward from `0.0` to `viewHeight`.
///
/// Preview Layer Aspect Fill Scaling:
/// When an `AVCaptureVideoPreviewLayer` uses `.resizeAspectFill`, the video buffer is uniformly scaled
/// until both dimensions meet or exceed the view bounds, centering the video and cropping the excess.
public enum CoordinateTransformer: Sendable {

    // MARK: - Geometry & Aspect Ratio Calculations

    /// Computes the aspect-fill scaled dimensions and centering offsets for a given view size and video aspect ratio.
    ///
    /// - Parameters:
    ///   - viewSize: Target display size of the SwiftUI/UIKit preview container.
    ///   - videoAspectRatio: Aspect ratio (width / height) of the camera stream. Defaults to portrait 9:16 (0.5625).
    /// - Returns: A tuple containing `scaledSize` and `offset` (centering offset within `viewSize`).
    public static func aspectFillGeometry(
        viewSize: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> (scaledSize: CGSize, offset: CGPoint) {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return (.zero, .zero)
        }

        let effectiveVideoRatio: CGFloat = videoAspectRatio > 0 ? videoAspectRatio : (viewSize.width / viewSize.height)
        let viewRatio = viewSize.width / viewSize.height

        let scaledWidth: CGFloat
        let scaledHeight: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if abs(viewRatio - effectiveVideoRatio) < 0.0001 {
            // View and video aspect ratios match: 1-to-1 fit without cropping.
            scaledWidth = viewSize.width
            scaledHeight = viewSize.height
            offsetX = 0.0
            offsetY = 0.0
        } else if viewRatio > effectiveVideoRatio {
            // View is wider than video relative to height -> video scales to match width, top/bottom cropped.
            scaledWidth = viewSize.width
            scaledHeight = viewSize.width / effectiveVideoRatio
            offsetX = 0.0
            offsetY = (viewSize.height - scaledHeight) / 2.0
        } else {
            // View is taller than video relative to width -> video scales to match height, left/right cropped.
            scaledHeight = viewSize.height
            scaledWidth = viewSize.height * effectiveVideoRatio
            offsetX = (viewSize.width - scaledWidth) / 2.0
            offsetY = 0.0
        }

        return (CGSize(width: scaledWidth, height: scaledHeight), CGPoint(x: offsetX, y: offsetY))
    }

    // MARK: - Vision to Screen Coordinate Conversion

    /// Converts a normalized Vision rectangle `(0...1, 0...1, origin bottom-left)` to SwiftUI / UIKit screen coordinates
    /// matching `.resizeAspectFill` geometry.
    ///
    /// - Parameters:
    ///   - visionRect: Normalized bounding box from Vision OCR (Y-up, origin bottom-left).
    ///   - viewSize: Size of the destination view in points.
    ///   - videoAspectRatio: Aspect ratio (width / height) of the video feed. Defaults to portrait 9:16.
    /// - Returns: Rectangle in screen coordinates (Y-down, origin top-left).
    public static func convert(
        visionRect: CGRect,
        viewSize: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let normalized = visionRect.standardized
        let (scaledSize, offset) = aspectFillGeometry(viewSize: viewSize, videoAspectRatio: videoAspectRatio)

        // Vision framework: origin is at bottom-left (Y increases upward).
        // normalized.origin.y is the bottom edge, normalized.maxY is the top edge.
        // Screen framework: origin is at top-left (Y increases downward).
        // Distance of top edge from top is: 1.0 - normalized.maxY = (1.0 - normalized.origin.y - normalized.size.height)
        let screenX = offset.x + (normalized.origin.x * scaledSize.width)
        let screenY = offset.y + ((1.0 - normalized.origin.y - normalized.size.height) * scaledSize.height)
        let screenWidth = normalized.size.width * scaledSize.width
        let screenHeight = normalized.size.height * scaledSize.height

        return CGRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
    }

    /// Converts a normalized Vision point `(0...1, 0...1, origin bottom-left)` to screen coordinates.
    ///
    /// - Parameters:
    ///   - visionPoint: Normalized point from Vision (Y-up, origin bottom-left).
    ///   - viewSize: Size of the destination view in points.
    ///   - videoAspectRatio: Aspect ratio (width / height) of the video feed. Defaults to portrait 9:16.
    /// - Returns: Point in screen coordinates (Y-down, origin top-left).
    public static func convert(
        visionPoint: CGPoint,
        viewSize: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let (scaledSize, offset) = aspectFillGeometry(viewSize: viewSize, videoAspectRatio: videoAspectRatio)
        let screenX = offset.x + (visionPoint.x * scaledSize.width)
        let screenY = offset.y + ((1.0 - visionPoint.y) * scaledSize.height)

        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Screen to Vision Coordinate Conversion (Inverse)

    /// Converts a rectangle from screen coordinates (Y-down, origin top-left) back to normalized Vision coordinates
    /// `(0...1, 0...1, origin bottom-left)`.
    ///
    /// - Parameters:
    ///   - screenRect: Bounding box in view points.
    ///   - viewSize: Size of the container view in points.
    ///   - videoAspectRatio: Aspect ratio of the video feed. Defaults to portrait 9:16.
    /// - Returns: Normalized Vision rectangle.
    public static func convertToVision(
        screenRect: CGRect,
        viewSize: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let standardized = screenRect.standardized
        let (scaledSize, offset) = aspectFillGeometry(viewSize: viewSize, videoAspectRatio: videoAspectRatio)

        guard scaledSize.width > 0, scaledSize.height > 0 else { return .zero }

        let visionX = (standardized.origin.x - offset.x) / scaledSize.width
        let visionWidth = standardized.size.width / scaledSize.width
        let visionHeight = standardized.size.height / scaledSize.height
        // In Vision, bottom edge Y is: 1.0 - (screenMaxY - offsetY) / scaledHeight
        let visionY = 1.0 - ((standardized.origin.y + standardized.size.height - offset.y) / scaledSize.height)

        return CGRect(x: visionX, y: visionY, width: visionWidth, height: visionHeight)
    }

    /// Converts a point from screen coordinates back to normalized Vision coordinates.
    ///
    /// - Parameters:
    ///   - screenPoint: Point in view points.
    ///   - viewSize: Size of the container view in points.
    ///   - videoAspectRatio: Aspect ratio of the video feed. Defaults to portrait 9:16.
    /// - Returns: Normalized Vision point.
    public static func convertToVision(
        screenPoint: CGPoint,
        viewSize: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let (scaledSize, offset) = aspectFillGeometry(viewSize: viewSize, videoAspectRatio: videoAspectRatio)
        guard scaledSize.width > 0, scaledSize.height > 0 else { return .zero }

        let visionX = (screenPoint.x - offset.x) / scaledSize.width
        let visionY = 1.0 - ((screenPoint.y - offset.y) / scaledSize.height)

        return CGPoint(x: visionX, y: visionY)
    }

    // MARK: - Exponential Moving Average (EMA) Smoothing

    /// Smooths a bounding box towards a target bounding box using an Exponential Moving Average (EMA) filter.
    ///
    /// Formula:
    /// `new_val = current + (target - current) * factor`
    ///
    /// Behavior:
    /// - When difference is negligible (< `pixelSnapThreshold`), snaps directly to `target` to eliminate subpixel micro-jitter.
    /// - When difference is very large (> `snapThreshold`), snaps directly to `target` to avoid lagging ghost boxes during camera sweeps.
    /// - Adaptively scales snap thresholds when operating in normalized (0...1) coordinate space.
    ///
    /// - Parameters:
    ///   - current: Currently rendered bounding box.
    ///   - target: Newly detected target bounding box.
    ///   - factor: Smoothing factor / alpha (0.0 = no movement, 1.0 = instant snap). Default is `0.35`.
    ///   - snapThreshold: Distance or size jump threshold above which the box immediately snaps to target. Default is `150.0` points.
    ///   - pixelSnapThreshold: Negligible distance threshold below which the box snaps to target. Default is `1.0` point.
    /// - Returns: Smoothed bounding box.
    public static func smooth(
        current: CGRect,
        target: CGRect,
        factor: CGFloat = 0.35,
        snapThreshold: CGFloat = 150.0,
        pixelSnapThreshold: CGFloat = 1.0
    ) -> CGRect {
        // Base edge case validations
        guard !target.isNull, !target.isEmpty, target != .zero else {
            return current
        }
        guard !current.isNull, !current.isEmpty, current != .zero else {
            return target
        }
        guard factor > 0 else { return current }
        guard factor < 1.0 else { return target }

        // Adaptive threshold scaling: if both rects are normalized (<= 1.5), scale thresholds accordingly.
        let isNormalized = target.maxX <= 1.5 && target.maxY <= 1.5 &&
                           current.maxX <= 1.5 && current.maxY <= 1.5
        let effectivePixelSnap = isNormalized ? min(pixelSnapThreshold, 0.002) : pixelSnapThreshold
        let effectiveLargeSnap = isNormalized ? min(snapThreshold, 0.25) : snapThreshold

        let dx = abs(target.origin.x - current.origin.x)
        let dy = abs(target.origin.y - current.origin.y)
        let dw = abs(target.size.width - current.size.width)
        let dh = abs(target.size.height - current.size.height)

        // 1. Negligible difference: snap to target to avoid continuous subpixel micro-jitter
        if dx < effectivePixelSnap && dy < effectivePixelSnap &&
           dw < effectivePixelSnap && dh < effectivePixelSnap {
            return target
        }

        // 2. Large sudden movement: snap to target to prevent lagging ghost boxes during camera whip or scene transitions
        let centerDistance = hypot(target.midX - current.midX, target.midY - current.midY)
        if centerDistance > effectiveLargeSnap || max(dx, dy, dw, dh) > effectiveLargeSnap {
            return target
        }

        // 3. Exponential Moving Average calculation
        let alpha = min(max(factor, 0.0), 1.0)
        let smoothedX = current.origin.x + (target.origin.x - current.origin.x) * alpha
        let smoothedY = current.origin.y + (target.origin.y - current.origin.y) * alpha
        let smoothedW = current.size.width + (target.size.width - current.size.width) * alpha
        let smoothedH = current.size.height + (target.size.height - current.size.height) * alpha

        let smoothed = CGRect(x: smoothedX, y: smoothedY, width: smoothedW, height: smoothedH)

        // Check if the smoothed position is within snapping distance of target
        if abs(target.origin.x - smoothed.origin.x) < effectivePixelSnap &&
           abs(target.origin.y - smoothed.origin.y) < effectivePixelSnap &&
           abs(target.size.width - smoothed.size.width) < effectivePixelSnap &&
           abs(target.size.height - smoothed.size.height) < effectivePixelSnap {
            return target
        }

        return smoothed
    }

    // MARK: - Intersection over Union (IoU)

    /// Computes Intersection over Union (IoU) between two bounding boxes.
    ///
    /// Formula:
    /// `IoU = Area(rect1 ∩ rect2) / Area(rect1 ∪ rect2)`
    ///
    /// - Parameters:
    ///   - rect1: First bounding box.
    ///   - rect2: Second bounding box.
    /// - Returns: Overlap score between `0.0` (disjoint) and `1.0` (identical).
    public static func intersectionOverUnion(_ rect1: CGRect, _ rect2: CGRect) -> CGFloat {
        let std1 = rect1.standardized
        let std2 = rect2.standardized

        guard !std1.isNull, !std1.isEmpty, !std2.isNull, !std2.isEmpty else {
            return 0.0
        }

        let intersection = std1.intersection(std2)
        if intersection.isNull || intersection.isEmpty {
            return 0.0
        }

        let area1 = std1.width * std1.height
        let area2 = std2.width * std2.height
        let intersectionArea = intersection.width * intersection.height
        let unionArea = area1 + area2 - intersectionArea

        guard unionArea > 0 else { return 0.0 }
        let score = intersectionArea / unionArea
        return min(max(score, 0.0), 1.0)
    }

    /// Convenience alias for `intersectionOverUnion`.
    public static func iou(_ rect1: CGRect, _ rect2: CGRect) -> CGFloat {
        intersectionOverUnion(rect1, rect2)
    }
}

// MARK: - Tracked Text Block

/// Represents a text block tracked temporally across consecutive video frames.
///
/// Features:
/// - Stable UUID across frames.
/// - Smoothed bounding box coordinates via EMA.
/// - Translation cache retention even if intermediate OCR frames lack translation.
/// - Decay counter (`missedFrames`) to prune stale detections.
public struct TrackedTextBlock: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var rawLines: [String]
    public var mergedText: String
    public var boundingBox: CGRect
    public var translatedText: String?
    public var sourceLanguage: String?
    public var missedFrames: Int
    public var firstDetectedTime: TimeInterval
    public var lastUpdatedTime: TimeInterval

    public init(
        id: UUID = UUID(),
        rawLines: [String],
        mergedText: String,
        boundingBox: CGRect,
        translatedText: String? = nil,
        sourceLanguage: String? = nil,
        missedFrames: Int = 0,
        firstDetectedTime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        lastUpdatedTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.id = id
        self.rawLines = rawLines
        self.mergedText = mergedText
        self.boundingBox = boundingBox
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.missedFrames = missedFrames
        self.firstDetectedTime = firstDetectedTime
        self.lastUpdatedTime = lastUpdatedTime
    }

    /// Initializes a `TrackedTextBlock` from a `DetectedTextBlock`.
    public init(detectedBlock: DetectedTextBlock) {
        self.init(
            id: detectedBlock.id,
            rawLines: detectedBlock.rawLines,
            mergedText: detectedBlock.mergedText,
            boundingBox: detectedBlock.boundingBox,
            translatedText: detectedBlock.translatedText,
            sourceLanguage: detectedBlock.sourceLanguage
        )
    }

    /// Converts this tracked text block to a `DetectedTextBlock`.
    public func toDetectedTextBlock() -> DetectedTextBlock {
        DetectedTextBlock(
            id: id,
            rawLines: rawLines,
            mergedText: mergedText,
            boundingBox: boundingBox,
            translatedText: translatedText,
            sourceLanguage: sourceLanguage
        )
    }
}

// MARK: - Box Tracker

/// Maintains temporal consistency of detected text blocks across consecutive video frames.
///
/// Algorithms:
/// 1. Computes Intersection over Union (IoU) between incoming detections and existing tracked blocks.
/// 2. Matches detections using greedy highest-IoU association above `iouThreshold`.
/// 3. Preserves stable `UUID` and previously fetched `translatedText`.
/// 4. Smooths bounding box geometry via Exponential Moving Average (`CoordinateTransformer.smooth`).
/// 5. Tracks unobserved blocks across frames and prunes them once `missedFrames > maxMissedFrames`.
public final class BoxTracker: @unchecked Sendable {

    private let lock = NSLock()
    private var _trackedBlocks: [TrackedTextBlock] = []

    /// Minimum Intersection over Union required to associate a detection with an existing tracked block. Default is `0.35`.
    public var iouThreshold: CGFloat

    /// Exponential Moving Average alpha factor for coordinate smoothing (0.0...1.0). Default is `0.35`.
    public var smoothingFactor: CGFloat

    /// Maximum consecutive frames a block can be missing before being pruned. Default is `3`.
    public var maxMissedFrames: Int

    /// Distance jump threshold to immediately snap bounding boxes. Default is `150.0` points.
    public var snapDistanceThreshold: CGFloat

    public init(
        iouThreshold: CGFloat = 0.35,
        smoothingFactor: CGFloat = 0.35,
        maxMissedFrames: Int = 3,
        snapDistanceThreshold: CGFloat = 150.0
    ) {
        self.iouThreshold = iouThreshold
        self.smoothingFactor = smoothingFactor
        self.maxMissedFrames = maxMissedFrames
        self.snapDistanceThreshold = snapDistanceThreshold
    }

    // MARK: - State Inspection

    /// All active tracked blocks (including temporarily missed blocks within `maxMissedFrames`).
    public var trackedBlocks: [TrackedTextBlock] {
        lock.lock()
        defer { lock.unlock() }
        return _trackedBlocks
    }

    /// All active tracked blocks converted to `[DetectedTextBlock]`.
    public var activeDetectedBlocks: [DetectedTextBlock] {
        lock.lock()
        defer { lock.unlock() }
        return _trackedBlocks.map { $0.toDetectedTextBlock() }
    }

    /// Only blocks detected in the most recent frame (`missedFrames == 0`).
    public var currentBlocks: [TrackedTextBlock] {
        lock.lock()
        defer { lock.unlock() }
        return _trackedBlocks.filter { $0.missedFrames == 0 }
    }

    /// Resets all tracking state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _trackedBlocks.removeAll()
    }

    // MARK: - Tracking Core

    /// Updates tracked blocks with newly detected blocks in the current frame.
    ///
    /// - Parameter blocks: Newly detected blocks from the OCR engine.
    /// - Returns: Updated array of `TrackedTextBlock`s.
    @discardableResult
    public func track(blocks: [DetectedTextBlock]) -> [TrackedTextBlock] {
        lock.lock()
        defer { lock.unlock() }

        let currentTime = ProcessInfo.processInfo.systemUptime
        var currentTracked = _trackedBlocks
        let newCount = blocks.count
        let oldCount = currentTracked.count

        // Case 1: Initial frame or empty previous state
        if oldCount == 0 {
            _trackedBlocks = blocks.map { TrackedTextBlock(detectedBlock: $0) }
            return _trackedBlocks
        }

        // Case 2: No detections in current frame -> decay existing tracked blocks
        if newCount == 0 {
            var updated: [TrackedTextBlock] = []
            for var block in currentTracked {
                block.missedFrames += 1
                if block.missedFrames <= maxMissedFrames {
                    updated.append(block)
                }
            }
            _trackedBlocks = updated
            return _trackedBlocks
        }

        // Case 3: Match incoming detections to existing tracked blocks via IoU
        struct MatchCandidate {
            let newIndex: Int
            let oldIndex: Int
            let iou: CGFloat
        }

        var candidates: [MatchCandidate] = []
        for i in 0..<newCount {
            for j in 0..<oldCount {
                let score = CoordinateTransformer.intersectionOverUnion(
                    blocks[i].boundingBox,
                    currentTracked[j].boundingBox
                )
                if score >= iouThreshold {
                    candidates.append(MatchCandidate(newIndex: i, oldIndex: j, iou: score))
                }
            }
        }

        // Sort descending by highest IoU overlap for optimal greedy association
        candidates.sort { $0.iou > $1.iou }

        var matchedNew = Set<Int>()
        var matchedOld = Set<Int>()
        var nextTrackedBlocks: [TrackedTextBlock] = []

        for candidate in candidates {
            if matchedNew.contains(candidate.newIndex) || matchedOld.contains(candidate.oldIndex) {
                continue
            }

            matchedNew.insert(candidate.newIndex)
            matchedOld.insert(candidate.oldIndex)

            let newBlock = blocks[candidate.newIndex]
            var tracked = currentTracked[candidate.oldIndex]

            // Apply EMA smoothing to bounding box
            tracked.boundingBox = CoordinateTransformer.smooth(
                current: tracked.boundingBox,
                target: newBlock.boundingBox,
                factor: smoothingFactor,
                snapThreshold: snapDistanceThreshold
            )

            // Update text content
            tracked.rawLines = newBlock.rawLines
            tracked.mergedText = newBlock.mergedText

            // Retain existing translation if new block has none; otherwise update
            if let newTranslation = newBlock.translatedText, !newTranslation.isEmpty {
                tracked.translatedText = newTranslation
            }

            if let newSourceLang = newBlock.sourceLanguage, !newSourceLang.isEmpty {
                tracked.sourceLanguage = newSourceLang
            }

            tracked.missedFrames = 0
            tracked.lastUpdatedTime = currentTime
            nextTrackedBlocks.append(tracked)
        }

        // Retain unmerged tracked blocks that haven't exceeded maxMissedFrames
        for j in 0..<oldCount {
            if !matchedOld.contains(j) {
                var missedBlock = currentTracked[j]
                missedBlock.missedFrames += 1
                if missedBlock.missedFrames <= maxMissedFrames {
                    nextTrackedBlocks.append(missedBlock)
                }
            }
        }

        // Introduce unmatched incoming detections as new tracked blocks
        for i in 0..<newCount {
            if !matchedNew.contains(i) {
                var newTracked = TrackedTextBlock(detectedBlock: blocks[i])
                newTracked.missedFrames = 0
                newTracked.firstDetectedTime = currentTime
                newTracked.lastUpdatedTime = currentTime
                nextTrackedBlocks.append(newTracked)
            }
        }

        _trackedBlocks = nextTrackedBlocks
        return _trackedBlocks
    }

    /// Convenience method to track blocks and return them as `[DetectedTextBlock]`.
    @discardableResult
    public func trackDetectedBlocks(_ blocks: [DetectedTextBlock]) -> [DetectedTextBlock] {
        track(blocks: blocks).map { $0.toDetectedTextBlock() }
    }

    // MARK: - Vision Conversion & End-to-End Tracking

    /// Converts normalized Vision text blocks to screen coordinates and tracks them temporally in screen space.
    ///
    /// - Parameters:
    ///   - visionBlocks: Text blocks with normalized Vision bounding boxes `(0...1)`.
    ///   - viewSize: Screen size of the display container in points.
    ///   - videoAspectRatio: Aspect ratio of the video feed. Defaults to portrait 9:16.
    /// - Returns: Smoothed screen-space `TrackedTextBlock`s.
    @discardableResult
    public func track(
        visionBlocks: [DetectedTextBlock],
        viewSize: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> [TrackedTextBlock] {
        let screenBlocks = visionBlocks.map { block in
            DetectedTextBlock(
                id: block.id,
                rawLines: block.rawLines,
                mergedText: block.mergedText,
                boundingBox: CoordinateTransformer.convert(
                    visionRect: block.boundingBox,
                    viewSize: viewSize,
                    videoAspectRatio: videoAspectRatio
                ),
                translatedText: block.translatedText,
                sourceLanguage: block.sourceLanguage
            )
        }
        return track(blocks: screenBlocks)
    }

    /// Converts normalized Vision text blocks to screen coordinates and tracks them, returning `[DetectedTextBlock]`.
    @discardableResult
    public func trackDetectedBlocks(
        visionBlocks: [DetectedTextBlock],
        viewSize: CGSize,
        videoAspectRatio: CGFloat = 9.0 / 16.0
    ) -> [DetectedTextBlock] {
        track(
            visionBlocks: visionBlocks,
            viewSize: viewSize,
            videoAspectRatio: videoAspectRatio
        ).map { $0.toDetectedTextBlock() }
    }

    // MARK: - Asynchronous Translation Updates

    /// Asynchronously updates the translated text and language of an existing tracked block by its stable ID.
    ///
    /// Useful when background translation jobs complete and push results into the tracker.
    ///
    /// - Parameters:
    ///   - blockId: Stable ID of the block to update.
    ///   - translatedText: The newly completed translation string.
    ///   - sourceLanguage: Optional detected source language identifier.
    /// - Returns: `true` if the block was found and updated, `false` otherwise.
    @discardableResult
    public func updateTranslation(
        for blockId: UUID,
        translatedText: String,
        sourceLanguage: String? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let index = _trackedBlocks.firstIndex(where: { $0.id == blockId }) else {
            return false
        }

        _trackedBlocks[index].translatedText = translatedText
        if let sourceLanguage = sourceLanguage {
            _trackedBlocks[index].sourceLanguage = sourceLanguage
        }
        _trackedBlocks[index].lastUpdatedTime = ProcessInfo.processInfo.systemUptime
        return true
    }
}
