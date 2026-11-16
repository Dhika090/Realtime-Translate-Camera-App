import SwiftUI
import AVFAudio
import UIKit

// MARK: - RomanizationHelper

/// Helper for generating phonetic Latin transliteration and Pinyin for CJK and non-Latin scripts
/// using Apple's Foundation `StringTransform` API.
public enum RomanizationHelper: Sendable {

    /// Generates phonetic Latin transliteration / Pinyin using Apple's Foundation `StringTransform`.
    ///
    /// For example:
    /// - `"牛肉面"` -> `"niú ròu miàn"`
    /// - `"你好"` -> `"nǐ hǎo"`
    /// - `"欢迎光临"` -> `"huān yíng guāng lín"`
    ///
    /// - Parameters:
    ///   - text: The input string (e.g. Chinese Hanzi, Japanese Kanji/Kana).
    ///   - stripDiacritics: If `true`, removes tone marks / accents (e.g. `"niu rou mian"`).
    /// - Returns: Romanized string if transliteration occurred, or `nil` if text is already Latin or empty.
    public static func romanize(_ text: String, stripDiacritics: Bool = false) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let latin = trimmed.applyingTransform(.toLatin, reverse: false) else {
            return nil
        }

        // If the transformed string is identical to input, no transliteration took place (e.g. already English/Latin)
        if latin == trimmed {
            return nil
        }

        if stripDiacritics {
            return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        }

        return latin
    }

    /// Convenience check for whether a string produces distinct phonetic romanization.
    public static func hasRomanization(for text: String) -> Bool {
        romanize(text) != nil
    }
}

// MARK: - TextToSpeechManager

/// Manages native text-to-speech synthesis using Apple's `AVSpeechSynthesizer`.
@MainActor
public final class TextToSpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // MARK: - Published Properties

    /// Indicates whether speech is currently in progress.
    @Published public private(set) var isSpeaking: Bool = false

    /// The text currently being spoken.
    @Published public private(set) var activeSpokenText: String? = nil

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Initialization

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speech Control

    /// Vocalizes the given text in the requested language voice.
    ///
    /// - Parameters:
    ///   - text: String to speak.
    ///   - languageCode: BCP-47 language tag (e.g. "zh-CN", "id-ID", "ja-JP", "en-US").
    ///   - rate: Speech rate multiplier (defaults to `AVSpeechUtteranceDefaultSpeechRate`).
    public func speak(
        text: String,
        languageCode: String = "zh-CN",
        rate: Float = AVSpeechUtteranceDefaultSpeechRate
    ) {
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let utterance = Self.makeUtterance(text: trimmed, languageCode: languageCode, rate: rate)
        activeSpokenText = trimmed
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stops any ongoing speech synthesis immediately.
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        activeSpokenText = nil
    }

    // MARK: - Utterance & Voice Factory

    /// Configures an `AVSpeechUtterance` for unit testing and audio playback.
    public static func makeUtterance(
        text: String,
        languageCode: String,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = resolveVoice(for: languageCode)
        return utterance
    }

    /// Resolves the optimal `AVSpeechSynthesisVoice` for a given language code.
    public static func resolveVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }

        // Direct exact match
        if let directVoice = AVSpeechSynthesisVoice(language: trimmed) {
            return directVoice
        }

        // Common language tag aliases
        let aliases: [String: String] = [
            "zh": "zh-CN",
            "zh-hans": "zh-CN",
            "zh-hant": "zh-TW",
            "chi": "zh-CN",
            "id": "id-ID",
            "ind": "id-ID",
            "en": "en-US",
            "ja": "ja-JP",
            "jpn": "ja-JP",
            "ko": "ko-KR",
            "kor": "ko-KR",
            "fr": "fr-FR",
            "de": "de-DE",
            "es": "es-ES",
            "it": "it-IT"
        ]

        let lowered = trimmed.lowercased()
        if let mapped = aliases[lowered], let voice = AVSpeechSynthesisVoice(language: mapped) {
            return voice
        }

        // Available voices search
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        if let prefixMatch = allVoices.first(where: { $0.language.lowercased().starts(with: lowered) }) {
            return prefixMatch
        }

        return AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.activeSpokenText = nil
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.activeSpokenText = nil
        }
    }
}

// MARK: - DetailCardSheet

/// Interactive bottom sheet presented when a user taps an AR text badge.
///
/// Features:
/// - Language pair route display (source flag -> target flag).
/// - Original recognized text with phonetic Pinyin / Romanization.
/// - Full translated text with offline status indicator.
/// - One-tap copy to clipboard with temporary confirmation badge.
/// - Text-to-speech audio pronunciation using `AVSpeechSynthesizer`.
/// - Native iOS 18 sheet presentation styling.
public struct DetailCardSheet: View {

    // MARK: - Properties

    /// The inspected tracked text block.
    public let block: TrackedTextBlock

    /// The target translation language. Defaults to Indonesian.
    public let targetLanguage: AppLanguage

    /// Optional dismiss callback.
    public let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var ttsManager = TextToSpeechManager()
    @State private var isCopied: Bool = false

    // MARK: - Initialization

    /// Creates a `DetailCardSheet` for a `TrackedTextBlock`.
    public init(
        block: TrackedTextBlock,
        targetLanguage: AppLanguage = .indonesian,
        onDismiss: (() -> Void)? = nil
    ) {
        self.block = block
        self.targetLanguage = targetLanguage
        self.onDismiss = onDismiss
    }

    /// Convenience initializer for a `DetectedTextBlock`.
    public init(
        detectedBlock: DetectedTextBlock,
        targetLanguage: AppLanguage = .indonesian,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            block: TrackedTextBlock(detectedBlock: detectedBlock),
            targetLanguage: targetLanguage,
            onDismiss: onDismiss
        )
    }

    // MARK: - Computed Properties

    /// Source language representation derived from block metadata.
    public var sourceLanguage: AppLanguage {
        if let code = block.sourceLanguage, let match = AppLanguage.from(code: code) {
            return match
        }
        return .simplifiedChinese
    }

    /// Language code passed to speech synthesizer for original text.
    public var sourceVoiceLanguageCode: String {
        block.sourceLanguage ?? "zh-CN"
    }

    /// Language code passed to speech synthesizer for translated text.
    public var targetVoiceLanguageCode: String {
        targetLanguage.bcp47Code
    }

    /// Phonetic Pinyin / Romanization for original text if applicable.
    public var romanizedText: String? {
        RomanizationHelper.romanize(block.mergedText)
    }

    /// Primary text to copy to clipboard (prefers translation, falls back to original).
    public var textToCopy: String {
        if let translated = block.translatedText, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated
        }
        return block.mergedText
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Header with language flags and route
                headerView

                // Main content sections
                ScrollView {
                    VStack(spacing: 14) {
                        originalTextSection
                        translatedTextSection
                    }
                    .padding(.top, 4)
                }

                // Action buttons (Copy, Pronounce, Dismiss)
                actionButtonsBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background(Color(UIColor.systemBackground))
            .navigationBarHidden(true)
        }
        .presentationDetents([.fraction(0.48), .medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            ttsManager.stop()
        }
    }

    // MARK: - Subviews

    /// Top header showing language pair direction and close button.
    private var headerView: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Text(sourceLanguage.flagEmoji)
                    .font(.title2)
                Text(sourceLanguage.localizedName)
                    .font(.subheadline.weight(.semibold))

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                Text(targetLanguage.flagEmoji)
                    .font(.title2)
                Text(targetLanguage.localizedName)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Button {
                dismiss()
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .accessibilityLabel("Tutup detail")
        }
    }

    /// Section displaying the original recognized text and Romanization/Pinyin.
    private var originalTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TEKS ASLI")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                Spacer()

                // Audio pronounce original button
                Button {
                    toggleSpeech(for: block.mergedText, languageCode: sourceVoiceLanguageCode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isSpeakingOriginal ? "stop.fill" : "speaker.wave.2")
                            .font(.caption)
                        Text(isSpeakingOriginal ? "Hentikan" : "Lafalkan")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.blue)
                }
            }

            Text(block.mergedText)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Pinyin / Romanization pill
            if let pinyin = romanizedText {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "textformat.abc")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 2)

                    Text(pinyin)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(.blue)
                        .italic()
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    /// Section displaying the translated text.
    private var translatedTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TERJEMAHAN (\(targetLanguage.localizedName.uppercased()))")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                Spacer()

                if let translated = block.translatedText, !translated.isEmpty {
                    Label("Offline", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.green)
                }
            }

            if let translated = block.translatedText, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(translated)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Sedang menerjemahkan...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    /// Bottom action bar providing Copy, Pronounce, and Dismiss buttons.
    private var actionButtonsBar: some View {
        HStack(spacing: 12) {
            // Salin Teks button
            Button {
                copyText()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    Text(isCopied ? "Tersalin!" : "Salin Teks")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isCopied ? Color.green.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                )
                .foregroundColor(isCopied ? .green : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCopied ? Color.green : Color.clear, lineWidth: 1.5)
                )
            }
            .accessibilityLabel("Salin hasil terjemahan ke papan klip")

            // Dengarkan (Pronounce) button
            Button {
                togglePrimarySpeech()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ttsManager.isSpeaking ? "stop.fill" : "speaker.wave.3.fill")
                    Text(ttsManager.isSpeaking ? "Hentikan" : "Dengarkan")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ttsManager.isSpeaking ? Color.orange : Color.blue)
                )
                .foregroundColor(.white)
            }
            .accessibilityLabel("Dengarkan pengucapan audio")
        }
    }

    // MARK: - Actions

    private var isSpeakingOriginal: Bool {
        ttsManager.isSpeaking && ttsManager.activeSpokenText == block.mergedText
    }

    private func togglePrimarySpeech() {
        if ttsManager.isSpeaking {
            ttsManager.stop()
        } else {
            // Pronounce original text by default (essential for navigating foreign menu dishes/signage)
            let speechText = block.mergedText
            ttsManager.speak(text: speechText, languageCode: sourceVoiceLanguageCode)
        }
    }

    private func toggleSpeech(for text: String, languageCode: String) {
        if ttsManager.isSpeaking && ttsManager.activeSpokenText == text {
            ttsManager.stop()
        } else {
            ttsManager.speak(text: text, languageCode: languageCode)
        }
    }

    private func copyText() {
        UIPasteboard.general.string = textToCopy
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCopied = false
                }
            }
        }
    }
}
