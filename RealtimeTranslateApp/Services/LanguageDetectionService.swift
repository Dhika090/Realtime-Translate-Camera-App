import Foundation
import NaturalLanguage

/// Service responsible for detecting the natural language of recognized text using Apple's `NaturalLanguage` framework.
///
/// Thread-safe and conforms to `Sendable`. Evaluates language hypotheses and enforces a configurable
/// confidence threshold to minimize false detections on short OCR snippets or noisy backgrounds.
public final class LanguageDetectionService: Sendable {

    /// Minimum confidence threshold (0.0 ... 1.0) required to consider a detection reliable.
    public let confidenceThreshold: Double

    /// Creates a new `LanguageDetectionService`.
    ///
    /// - Parameter confidenceThreshold: Minimum confidence score required (defaults to 0.2).
    public init(confidenceThreshold: Double = 0.2) {
        self.confidenceThreshold = confidenceThreshold
    }

    /// Detects the dominant language in the provided text string.
    ///
    /// - Parameter text: The input string to analyze.
    /// - Returns: The highest-confidence detected `Locale.Language`, or `nil` if text is empty,
    ///   undetermined, or the confidence score does not satisfy `confidenceThreshold`.
    public func detectDominantLanguage(text: String) -> Locale.Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            return nil
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        if let confidence = hypotheses[dominant] {
            guard confidence >= confidenceThreshold else { return nil }
        } else if let firstConfidence = hypotheses.values.first {
            guard firstConfidence >= confidenceThreshold else { return nil }
        }

        return Locale.Language(identifier: dominant.rawValue)
    }

    /// Convenience method returning the ISO-639 / BCP-47 language code string (e.g. "zh", "id", "en").
    ///
    /// - Parameter text: The input string to analyze.
    /// - Returns: The language code string, or `nil` if language could not be reliably determined.
    public func detectLanguageCode(text: String) -> String? {
        guard let language = detectDominantLanguage(text: text) else { return nil }
        return language.languageCode?.identifier
    }

    /// Detects the best matching `AppLanguage` preset for the provided text.
    ///
    /// - Parameter text: The input string to analyze.
    /// - Returns: The best-matching `AppLanguage`, or `nil` if unidentified.
    public func detectAppLanguage(text: String) -> AppLanguage? {
        guard let dominant = detectDominantLanguage(text: text) else { return nil }
        return AppLanguage.from(locale: dominant)
    }
}
