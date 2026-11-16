import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Vision

// MARK: - OCR Error

/// Errors that can occur during text recognition and frame processing.
public enum OCRError: LocalizedError, Equatable, Sendable {
    case frameThrottled
    case recognitionFailed(String)
    case invalidInput
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .frameThrottled:
            return "Frame dropped due to active in-flight processing or throttle rate limit."
        case .recognitionFailed(let message):
            return "Vision text recognition failed: \(message)"
        case .invalidInput:
            return "Invalid image or pixel buffer provided to OCR service."
        case .cancelled:
            return "Text recognition task was cancelled."
        }
    }
}

// MARK: - OCR Configuration

/// Configuration parameters for `VNRecognizeTextRequest` and the OCR processing pipeline.
public struct OCRConfiguration: Equatable, Sendable {
    /// Recognition fidelity level (.accurate or .fast). Defaults to .accurate.
    public var recognitionLevel: VNRequestTextRecognitionLevel

    /// Whether Vision uses language correction to improve recognition accuracy.
    public var usesLanguageCorrection: Bool

    /// Target language codes in BCP-47 / ISO format for text recognition.
    public var recognitionLanguages: [String]

    /// Whether Vision automatically detects languages in the frame.
    public var automaticallyDetectsLanguage: Bool

    /// Minimum confidence threshold (0.0 to 1.0) below which recognized lines are discarded.
    public var minimumConfidence: Float

    /// Minimum relative text height relative to image height (0.0 to 1.0).
    public var minimumTextHeight: Float

    /// Maximum vertical distance between adjacent lines for spatial clustering.
    public var lineSpacingThreshold: CGFloat

    /// Minimum time interval in seconds between consecutive processed frames (e.g. 0.15s = ~6.7 Hz).
    public var minimumFrameInterval: TimeInterval

    /// Default recognition languages including Asian scripts (Chinese, Japanese, Korean) and Latin scripts.
    public static let defaultRecognitionLanguages: [String] = [
        "zh-Hans", "zh-Hant", "en-US", "id-ID",
        "ja-JP", "ko-KR", "es-ES", "fr-FR", "de-DE"
    ]

    /// Default configuration tailored for real-time camera translation.
    public static let `default` = OCRConfiguration(
        recognitionLevel: .accurate,
        usesLanguageCorrection: true,
        recognitionLanguages: defaultRecognitionLanguages,
        automaticallyDetectsLanguage: true,
        minimumConfidence: 0.3,
        minimumTextHeight: 0.0,
        lineSpacingThreshold: 0.04,
        minimumFrameInterval: 0.15
    )

    public init(
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true,
        recognitionLanguages: [String] = defaultRecognitionLanguages,
        automaticallyDetectsLanguage: Bool = true,
        minimumConfidence: Float = 0.3,
        minimumTextHeight: Float = 0.0,
        lineSpacingThreshold: CGFloat = 0.04,
        minimumFrameInterval: TimeInterval = 0.15
    ) {
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
        self.recognitionLanguages = recognitionLanguages
        self.automaticallyDetectsLanguage = automaticallyDetectsLanguage
        self.minimumConfidence = minimumConfidence
        self.minimumTextHeight = minimumTextHeight
        self.lineSpacingThreshold = lineSpacingThreshold
        self.minimumFrameInterval = minimumFrameInterval
    }
}

// MARK: - Frame Throttler

/// Thread-safe throttler and concurrency limiter for real-time camera frames.
///
/// Ensures heavy Vision OCR inferences are executed at a controlled cadence (e.g. 5-10 Hz)
/// and drops incoming frames whenever an inference request is already in-flight.
public final class FrameThrottler: @unchecked Sendable {
    private let lock = NSLock()
    private var _isProcessing: Bool = false
    private var _lastProcessedDate: Date?
    private let clock: @Sendable () -> Date

    /// Minimum interval in seconds required between successive frame starts.
    public var minimumInterval: TimeInterval

    public init(
        minimumInterval: TimeInterval = 0.15,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.minimumInterval = minimumInterval
        self.clock = clock
    }

    /// Indicates whether an OCR request is currently executing in-flight.
    public var isProcessing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isProcessing
    }

    /// The timestamp when the last frame inference was initiated.
    public var lastProcessedDate: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _lastProcessedDate
    }

    /// Checks whether an incoming frame should be processed based on busy state and throttle interval.
    ///
    /// - Parameter date: Optional override timestamp (useful for deterministic unit testing).
    /// - Returns: `true` if no frame is currently processing and the minimum interval has elapsed.
    public func shouldProcessFrame(at date: Date? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = date ?? clock()

        guard !_isProcessing else { return false }

        if let last = _lastProcessedDate {
            return now.timeIntervalSince(last) >= minimumInterval
        }
        return true
    }

    /// Atomically tests if the frame should be processed, and if so, marks processing as active.
    ///
    /// - Parameter date: Optional override timestamp.
    /// - Returns: `true` if the frame was successfully acquired for processing; `false` if dropped.
    public func acquireFrame(at date: Date? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = date ?? clock()

        guard !_isProcessing else { return false }

        if let last = _lastProcessedDate {
            guard now.timeIntervalSince(last) >= minimumInterval else {
                return false
            }
        }

        _isProcessing = true
        _lastProcessedDate = now
        return true
    }

    /// Releases the active processing lock once an inference completes or fails.
    public func releaseFrame() {
        lock.lock()
        defer { lock.unlock() }
        _isProcessing = false
    }

    /// Resets the throttler state (clears active flag and timestamp history).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _isProcessing = false
        _lastProcessedDate = nil
    }
}

// MARK: - Vision Text Recognizer Protocol

/// Abstract interface for text recognition to allow mocking and unit testing without hardware dependencies.
public protocol VisionTextRecognizerProtocol: Sendable {
    func recognizeText(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        configuration: OCRConfiguration
    ) throws -> [OCRLine]

    func recognizeText(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        configuration: OCRConfiguration
    ) throws -> [OCRLine]
}

// MARK: - Default Vision Text Recognizer

/// Native Vision framework text recognizer implementation utilizing `VNRecognizeTextRequest`.
public struct DefaultVisionTextRecognizer: VisionTextRecognizerProtocol {
    public init() {}

    public func recognizeText(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        configuration: OCRConfiguration
    ) throws -> [OCRLine] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        return try performRequest(with: handler, configuration: configuration)
    }

    public func recognizeText(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        configuration: OCRConfiguration
    ) throws -> [OCRLine] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return try performRequest(with: handler, configuration: configuration)
    }

    private func performRequest(
        with handler: VNImageRequestHandler,
        configuration: OCRConfiguration
    ) throws -> [OCRLine] {
        var recognizedLines: [OCRLine] = []
        var requestError: Error?

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                requestError = error
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                if candidate.confidence >= configuration.minimumConfidence {
                    let line = OCRLine(
                        text: candidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    )
                    recognizedLines.append(line)
                }
            }
        }

        request.recognitionLevel = configuration.recognitionLevel
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        request.recognitionLanguages = configuration.recognitionLanguages
        request.automaticallyDetectsLanguage = configuration.automaticallyDetectsLanguage

        if configuration.minimumTextHeight > 0 {
            request.minimumTextHeight = configuration.minimumTextHeight
        }

        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        if let requestError = requestError {
            throw OCRError.recognitionFailed(requestError.localizedDescription)
        }

        return recognizedLines
    }
}

// MARK: - OCR Service Protocol

/// Service interface for processing camera frames and static images into clustered text blocks.
public protocol OCRServiceProtocol: Sendable {
    var configuration: OCRConfiguration { get }
    var throttler: FrameThrottler { get }

    /// Checks if a new frame should be submitted for processing.
    func shouldProcessFrame() -> Bool

    /// Processes a live camera pixel buffer and produces clustered text blocks.
    func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        ignoreThrottling: Bool
    ) async throws -> [DetectedTextBlock]

    /// Processes a static CGImage and produces clustered text blocks.
    func process(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        ignoreThrottling: Bool
    ) async throws -> [DetectedTextBlock]
}

extension OCRServiceProtocol {
    public func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [DetectedTextBlock] {
        try await process(pixelBuffer: pixelBuffer, orientation: orientation, ignoreThrottling: false)
    }

    public func process(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [DetectedTextBlock] {
        try await process(cgImage: cgImage, orientation: orientation, ignoreThrottling: false)
    }
}

// MARK: - OCR Service Implementation

/// Core Vision OCR service that consumes camera frames, performs throttled on-device text recognition,
/// and clusters recognized text lines into semantic blocks via `SpatialTextClusterer`.
public final class OCRService: OCRServiceProtocol, Sendable {
    public let configuration: OCRConfiguration
    public let clusterer: SpatialTextClusterer
    public let throttler: FrameThrottler
    private let recognizer: VisionTextRecognizerProtocol

    public init(
        configuration: OCRConfiguration = .default,
        clusterer: SpatialTextClusterer = SpatialTextClusterer(),
        throttler: FrameThrottler? = nil,
        recognizer: VisionTextRecognizerProtocol? = nil
    ) {
        self.configuration = configuration
        self.clusterer = clusterer
        self.throttler = throttler ?? FrameThrottler(minimumInterval: configuration.minimumFrameInterval)
        self.recognizer = recognizer ?? DefaultVisionTextRecognizer()
    }

    /// Fast non-blocking query to determine whether a camera frame should be processed.
    public func shouldProcessFrame() -> Bool {
        throttler.shouldProcessFrame()
    }

    /// Processes a camera frame pixel buffer with frame throttling and spatial clustering.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The raw video frame pixel buffer from AVFoundation.
    ///   - orientation: The image orientation of the buffer (defaults to `.up`).
    ///   - ignoreThrottling: If `true`, bypasses throttle limits (e.g. for freeze-frame capture).
    /// - Returns: Clustered semantic text blocks ready for translation.
    /// - Throws: `OCRError.frameThrottled` if throttled, or `OCRError.recognitionFailed` on failure.
    public func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up,
        ignoreThrottling: Bool = false
    ) async throws -> [DetectedTextBlock] {
        if !ignoreThrottling {
            guard throttler.acquireFrame() else {
                throw OCRError.frameThrottled
            }
        }
        defer {
            if !ignoreThrottling {
                throttler.releaseFrame()
            }
        }

        let lines = try recognizer.recognizeText(
            in: pixelBuffer,
            orientation: orientation,
            configuration: configuration
        )

        return clusterer.cluster(
            lines: lines,
            lineSpacingThreshold: configuration.lineSpacingThreshold
        )
    }

    /// Processes a static CGImage with spatial clustering.
    ///
    /// - Parameters:
    ///   - cgImage: The CoreGraphics image to recognize.
    ///   - orientation: The image orientation (defaults to `.up`).
    ///   - ignoreThrottling: If `true`, bypasses throttle limits.
    /// - Returns: Clustered semantic text blocks ready for translation.
    /// - Throws: `OCRError.frameThrottled` if throttled, or `OCRError.recognitionFailed` on failure.
    public func process(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        ignoreThrottling: Bool = false
    ) async throws -> [DetectedTextBlock] {
        if !ignoreThrottling {
            guard throttler.acquireFrame() else {
                throw OCRError.frameThrottled
            }
        }
        defer {
            if !ignoreThrottling {
                throttler.releaseFrame()
            }
        }

        let lines = try recognizer.recognizeText(
            in: cgImage,
            orientation: orientation,
            configuration: configuration
        )

        return clusterer.cluster(
            lines: lines,
            lineSpacingThreshold: configuration.lineSpacingThreshold
        )
    }

    /// Convenience helper to cluster already-recognized OCR lines directly using this service's configuration.
    public func cluster(lines: [OCRLine]) -> [DetectedTextBlock] {
        clusterer.cluster(
            lines: lines,
            lineSpacingThreshold: configuration.lineSpacingThreshold
        )
    }
}
