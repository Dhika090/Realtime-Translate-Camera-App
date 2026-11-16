import Foundation

#if canImport(Translation)
import Translation
#endif

// MARK: - Availability Status

/// Represents the availability state of on-device translation for a given language pair.
public enum TranslationAvailabilityStatus: String, Sendable, Equatable, Hashable {
    /// The on-device translation model is downloaded and ready for immediate offline use.
    case installed

    /// The language pair is supported by Apple Translation, but model assets may require on-demand download.
    case supported

    /// The requested language pair is not supported.
    case unsupported
}

// MARK: - Errors

/// Translation service specific errors.
public enum TranslationServiceError: LocalizedError, Sendable, Equatable {
    case unsupportedLanguagePair(source: String?, target: String)
    case sessionUnavailable
    case translationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLanguagePair(let source, let target):
            return "The language pair from '\(source ?? "auto")' to '\(target)' is unsupported."
        case .sessionUnavailable:
            return "Translation session is unavailable. Ensure a valid TranslationSession is active."
        case .translationFailed(let message):
            return "Translation failed: \(message)"
        }
    }
}

// MARK: - TranslationSessionAdapter Protocol

/// Abstraction allowing `TranslationService` to consume Apple's iOS 18 `TranslationSession`
/// or simulated/mock session adapters interchangeably.
public protocol TranslationSessionAdapter: Sendable {
    /// Translates an array of strings in a batch.
    ///
    /// - Parameter texts: An array of source strings to translate.
    /// - Returns: An array of translated strings matching the input order.
    func translate(batch texts: [String]) async throws -> [String]
}

// MARK: - Apple Translation Adapter (iOS 18+)

#if canImport(Translation)
/// Native iOS 18 `TranslationSession` adapter wrapping Apple's batch translation API.
@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
public struct AppleTranslationSessionAdapter: TranslationSessionAdapter {
    private let session: TranslationSession

    public init(session: TranslationSession) {
        self.session = session
    }

    public func translate(batch texts: [String]) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        let requests = texts.map { TranslationSession.Request(sourceText: $0) }
        let responses = try await session.translate(batch: requests)
        return responses.map(\.targetText)
    }
}
#endif

// MARK: - TranslationServiceProtocol

/// Defines the contract for language availability checks and batch translation.
public protocol TranslationServiceProtocol: Sendable {
    /// Checks whether on-device translation is installed, supported, or unsupported for the pair.
    ///
    /// - Parameters:
    ///   - source: The source language, or `nil` for automatic detection.
    ///   - target: The target language.
    /// - Returns: The current availability status.
    func checkAvailability(from source: Locale.Language?, to target: Locale.Language) async -> TranslationAvailabilityStatus

    /// Translates a batch of text strings from source to target language.
    ///
    /// - Parameters:
    ///   - texts: The array of input strings to translate.
    ///   - source: The source language, or `nil` for automatic detection.
    ///   - target: The target language.
    /// - Returns: An array of translated strings in corresponding order.
    func translate(texts: [String], source: Locale.Language?, target: Locale.Language) async throws -> [String]
}

extension TranslationServiceProtocol {
    /// Convenience method for translating a single text string.
    public func translate(
        text: String,
        source: Locale.Language?,
        target: Locale.Language
    ) async throws -> String {
        let results = try await translate(texts: [text], source: source, target: target)
        guard let first = results.first else {
            throw TranslationServiceError.translationFailed("Empty translation response.")
        }
        return first
    }
}

// MARK: - TranslationService Implementation

/// Implementation of `TranslationServiceProtocol` leveraging Apple's iOS 18 `Translation` framework.
///
/// Designed to support:
/// - Real-time batch translation via Apple's `TranslationSession` adapter.
/// - Offline simulation / fallback for Xcode previews and unit tests without hardware session.
/// - Dynamic session updating via `.translationTask`.
public final class TranslationService: TranslationServiceProtocol, @unchecked Sendable {

    public typealias TranslationFallbackHandler = @Sendable ([String], Locale.Language?, Locale.Language) async throws -> [String]
    public typealias AvailabilityCheckHandler = @Sendable (Locale.Language?, Locale.Language) async -> TranslationAvailabilityStatus

    private let lock = NSLock()
    private var _sessionAdapter: (any TranslationSessionAdapter)?
    private var _fallbackHandler: TranslationFallbackHandler?
    private var _availabilityHandler: AvailabilityCheckHandler?
    private var _forceFallback: Bool

    /// Creates a new `TranslationService`.
    ///
    /// - Parameters:
    ///   - sessionAdapter: An optional session adapter (e.g. `AppleTranslationSessionAdapter` or mock).
    ///   - availabilityHandler: Custom availability check handler (primarily for tests).
    ///   - fallbackHandler: Custom fallback translation handler.
    ///   - forceFallback: When `true`, forces using the fallback mechanism even if an adapter is attached.
    public init(
        sessionAdapter: (any TranslationSessionAdapter)? = nil,
        availabilityHandler: AvailabilityCheckHandler? = nil,
        fallbackHandler: TranslationFallbackHandler? = nil,
        forceFallback: Bool = false
    ) {
        self._sessionAdapter = sessionAdapter
        self._availabilityHandler = availabilityHandler
        self._fallbackHandler = fallbackHandler
        self._forceFallback = forceFallback
    }

    /// Sets or clears the active session adapter.
    public func setSessionAdapter(_ adapter: (any TranslationSessionAdapter)?) {
        lock.lock()
        defer { lock.unlock() }
        self._sessionAdapter = adapter
    }

    #if canImport(Translation)
    /// Registers an Apple `TranslationSession` obtained from SwiftUI's `.translationTask`.
    @available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
    public func setTranslationSession(_ session: TranslationSession) {
        setSessionAdapter(AppleTranslationSessionAdapter(session: session))
    }
    #endif

    /// Sets a custom fallback translation handler.
    public func setFallbackHandler(_ handler: TranslationFallbackHandler?) {
        lock.lock()
        defer { lock.unlock() }
        self._fallbackHandler = handler
    }

    /// Sets a custom availability check handler.
    public func setAvailabilityHandler(_ handler: AvailabilityCheckHandler?) {
        lock.lock()
        defer { lock.unlock() }
        self._availabilityHandler = handler
    }

    /// Toggles forced fallback mode (useful for testing and previews).
    public func setForceFallback(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self._forceFallback = enabled
    }

    // MARK: - TranslationServiceProtocol

    public func checkAvailability(
        from source: Locale.Language?,
        to target: Locale.Language
    ) async -> TranslationAvailabilityStatus {
        let (customAvailability, _, _) = getHandlers()
        if let custom = customAvailability {
            return await custom(source, target)
        }

        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
            let availability = LanguageTranslationAvailability()
            let status = await availability.status(from: source, to: target)
            switch status {
            case .installed:
                return .installed
            case .supported:
                return .supported
            case .unsupported:
                return .unsupported
            @unknown default:
                return .unsupported
            }
        }
        #endif

        return .supported
    }

    public func translate(
        texts: [String],
        source: Locale.Language?,
        target: Locale.Language
    ) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        // Short-circuit if all texts are blank
        let hasNonEmpty = texts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasNonEmpty else { return texts }

        let (_, adapter, fallbackHandler, forceFallback) = getActiveConfiguration()

        if !forceFallback, let adapter = adapter {
            do {
                return try await adapter.translate(batch: texts)
            } catch {
                if let fallback = fallbackHandler {
                    return try await fallback(texts, source, target)
                }
                throw TranslationServiceError.translationFailed(error.localizedDescription)
            }
        }

        if let fallback = fallbackHandler {
            return try await fallback(texts, source, target)
        }

        // Built-in simulated offline translation for previews / unit tests
        return try await defaultSimulatedTranslation(texts: texts, source: source, target: target)
    }

    // MARK: - Private Helpers

    private func getHandlers() -> (AvailabilityCheckHandler?, TranslationFallbackHandler?, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (_availabilityHandler, _fallbackHandler, _forceFallback)
    }

    private func getActiveConfiguration() -> (AvailabilityCheckHandler?, (any TranslationSessionAdapter)?, TranslationFallbackHandler?, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (_availabilityHandler, _sessionAdapter, _fallbackHandler, _forceFallback)
    }

    private func defaultSimulatedTranslation(
        texts: [String],
        source: Locale.Language?,
        target: Locale.Language
    ) async throws -> [String] {
        let targetCode = target.languageCode?.identifier ?? "id"
        return texts.map { text in
            simulateSingleTranslation(text: text, targetCode: targetCode)
        }
    }

    private func simulateSingleTranslation(text: String, targetCode: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Direct dictionary match for Indonesian target
        if targetCode == "id" {
            if let directMatch = Self.phraseDictionaryID[trimmed] {
                return directMatch
            }

            // Substring search for common restaurant keywords
            for (pattern, translation) in Self.phraseDictionaryID {
                if trimmed.contains(pattern) {
                    return trimmed.replacingOccurrences(of: pattern, with: translation)
                }
            }

            return "[ID] \(trimmed)"
        }

        // Direct dictionary match for English target
        if targetCode == "en" {
            if let directMatch = Self.phraseDictionaryEN[trimmed] {
                return directMatch
            }
            return "[EN] \(trimmed)"
        }

        return "[\(targetCode.uppercased())] \(trimmed)"
    }

    // MARK: - Built-in Phrase Dictionaries for Simulation & Offline Preview

    private static let phraseDictionaryID: [String: String] = [
        // Chinese -> Indonesian
        "欢迎光临 餐厅": "Selamat Datang di Restoran",
        "欢迎光临": "Selamat Datang",
        "红烧牛肉面": "Mie Daging Sapi Rebus Merah",
        "牛肉面": "Mie Daging Sapi",
        "清汤面": "Mie Kuah Bening",
        "炒饭": "Nasi Goreng",
        "扬州炒饭": "Nasi Goreng Yangzhou",
        "水饺": "Pangsit Air",
        "小笼包": "Xiao Long Bao",
        "麻婆豆腐": "Tahu Mapo",
        "宫保鸡丁": "Ayam Kung Pao",
        "精选新鲜食材传统工艺熬制浓郁鲜香汤底": "Bahan segar pilihan dimasak tradisional kaldu lezat gurih",
        "精选新鲜食材": "Bahan Segar Pilihan",
        "传统工艺熬制": "Dimasak Tradisional",
        "浓郁鲜香汤底": "Kaldu Lezat Gurih",
        "结账": "Kasir / Pembayaran",
        "洗手间": "Toilet",
        "出口": "Pintu Keluar",
        "入口": "Pintu Masuk",
        "菜单": "Daftar Menu",
        "特价": "Harga Spesial",

        // English -> Indonesian
        "Welcome to our Restaurant": "Selamat Datang di Restoran Kami",
        "Selamat Datang di Restoran Kami": "Selamat Datang di Restoran Kami",
        "Fresh roast beef and coffee": "Daging sapi panggang segar dan kopi",
        "Special Lunch Menu": "Menu Makan Siang Spesial",
        "Special": "Spesial",
        "Lunch Menu": "Menu Makan Siang",
        "Today's Special": "Spesial Hari Ini",
        "Coffee & Tea": "Kopi & Teh",
        "Exit": "Keluar",
        "Entrance": "Masuk",
        "Restroom": "Toilet",
        "Cashier": "Kasir",
        "Open": "Buka",
        "Closed": "Tutup",
        "Header": "Judul",
        "Footer": "Catatan Bawah"
    ]

    private static let phraseDictionaryEN: [String: String] = [
        "欢迎光临 餐厅": "Welcome to the Restaurant",
        "欢迎光临": "Welcome",
        "红烧牛肉面": "Braised Beef Noodles",
        "Selamat Datang di Restoran Kami": "Welcome to our Restaurant",
        "Selamat Datang": "Welcome",
        "Restoran": "Restaurant"
    ]
}
