import SwiftUI
import CoreGraphics

// MARK: - ARTextBadgeView

/// A frosted-glass floating badge displaying translated or recognized text,
/// positioned directly above the detected visual text in the camera feed.
///
/// Visual Specifications:
/// - Background: `.ultraThinMaterial` (frosted glass) with rounded rectangle / capsule corners (`cornerRadius: 8`).
/// - Border: Thin translucent stroke (`Color.white.opacity(0.35)`) or glowing accent when selected (`Color.blue`).
/// - Foreground: High-contrast legible text (`.white`), bold typography, dynamic scaling (`.minimumScaleFactor(0.6)`), `.lineLimit(3)`.
/// - State Styling: Distinct border glow and scale when `isSelected == true`.
/// - Translation Indicator: Subtle language badge or checkmark when translated text is available.
/// - Tap Gesture: Fires `onTap()` closure to present the inspection detail card sheet.
public struct ARTextBadgeView: View {

    // MARK: - Properties

    /// The original recognized text from OCR.
    public let originalText: String

    /// The translated text, or `nil` if translation is still in flight or unavailable.
    public let translatedText: String?

    /// Whether this badge is currently selected by the user.
    public let isSelected: Bool

    /// Target language code to display on the subtle badge (e.g. "ID"). Defaults to "ID".
    public let targetLanguageCode: String?

    /// Action triggered when the user taps this badge.
    public let onTap: () -> Void

    // MARK: - Initialization

    /// Creates an `ARTextBadgeView` with explicit text and selection parameters.
    public init(
        originalText: String,
        translatedText: String? = nil,
        isSelected: Bool = false,
        targetLanguageCode: String? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.isSelected = isSelected
        self.targetLanguageCode = targetLanguageCode
        self.onTap = onTap
    }

    /// Convenience initializer from a `TrackedTextBlock`.
    public init(
        block: TrackedTextBlock,
        isSelected: Bool = false,
        targetLanguageCode: String? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.init(
            originalText: block.mergedText,
            translatedText: block.translatedText,
            isSelected: isSelected,
            targetLanguageCode: targetLanguageCode,
            onTap: onTap
        )
    }

    /// Convenience initializer from a `DetectedTextBlock`.
    public init(
        block: DetectedTextBlock,
        isSelected: Bool = false,
        targetLanguageCode: String? = nil,
        onTap: @escaping () -> Void = {}
    ) {
        self.init(
            originalText: block.mergedText,
            translatedText: block.translatedText,
            isSelected: isSelected,
            targetLanguageCode: targetLanguageCode,
            onTap: onTap
        )
    }

    // MARK: - Computed Properties

    /// Indicates whether translated text is present and non-empty.
    public var hasTranslation: Bool {
        guard let translated = translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !translated.isEmpty
    }

    /// Text displayed on the primary badge face.
    public var displayText: String {
        if hasTranslation, let translated = translatedText {
            return translated
        }
        return originalText
    }

    /// Display language indicator badge text (e.g. "ID").
    public var languageBadgeText: String {
        targetLanguageCode?.uppercased() ?? "ID"
    }

    // MARK: - Body

    public var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Main text label
            Text(displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Subtle indicator badge for translated status
            if hasTranslation {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .black))
                    Text(languageBadgeText)
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.blue.opacity(0.85))
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.blue : Color.white.opacity(0.35),
                    lineWidth: isSelected ? 2.0 : 0.75
                )
        )
        .shadow(
            color: isSelected ? Color.blue.opacity(0.7) : Color.black.opacity(0.4),
            radius: isSelected ? 7 : 3,
            x: 0,
            y: isSelected ? 0 : 1.5
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasTranslation ? "Terjemahan: \(displayText)" : "Teks asli: \(displayText)")
        .accessibilityHint("Ketuk dua kali untuk memeriksa detail dan mendengarkan pengucapan")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
