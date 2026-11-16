import Foundation
import CoreGraphics

/// Represents a single recognized line of text from the OCR engine with normalized coordinates (0...1).
///
/// In Vision framework's coordinate space:
/// - (0, 0) is the bottom-left corner.
/// - (1, 1) is the top-right corner.
/// - `boundingBox` properties are normalized between 0.0 and 1.0.
public struct OCRLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var boundingBox: CGRect
    public var confidence: Float

    public init(
        id: UUID = UUID(),
        text: String,
        boundingBox: CGRect,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Represents a semantic block of text clustered from one or more spatially adjacent `OCRLine` elements.
///
/// Provides raw lines, unified merged text (handling CJK script concatenation without spaces),
/// the union bounding box, and placeholders for translation metadata.
public struct DetectedTextBlock: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var rawLines: [String]
    public var mergedText: String
    public var boundingBox: CGRect
    public var translatedText: String?
    public var sourceLanguage: String?

    public init(
        id: UUID = UUID(),
        rawLines: [String],
        mergedText: String,
        boundingBox: CGRect,
        translatedText: String? = nil,
        sourceLanguage: String? = nil
    ) {
        self.id = id
        self.rawLines = rawLines
        self.mergedText = mergedText
        self.boundingBox = boundingBox
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
    }
}
