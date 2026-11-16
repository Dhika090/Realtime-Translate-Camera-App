import Foundation

// MARK: - AppLanguage

/// Represents a supported language or auto-detect mode in the application.
public struct AppLanguage: Identifiable, Equatable, Hashable, Sendable {
    /// Unique identifier for the language, typically matching the BCP-47 code or "auto".
    public let id: String

    /// BCP-47 language tag (e.g., "id", "zh-Hans", "zh-Hant", "en", "ja", "ko").
    public let bcp47Code: String

    /// User-friendly display name (e.g. "Bahasa Indonesia", "Chinese (Mandarin, Simplified) - 中文", "English").
    public let name: String

    /// Localized name in the current system locale or English default.
    public let localizedName: String

    /// Flag emoji representing the language region.
    public let flagEmoji: String

    /// Indicates whether this represents automatic language detection.
    public let isAutoDetect: Bool

    /// Corresponding Swift Foundation `Locale.Language`, or `nil` if auto-detect.
    public var localeLanguage: Locale.Language? {
        if isAutoDetect {
            return nil
        }
        return Locale.Language(identifier: bcp47Code)
    }

    /// Creates an `AppLanguage` instance.
    public init(
        id: String? = nil,
        bcp47Code: String,
        name: String,
        localizedName: String,
        flagEmoji: String,
        isAutoDetect: Bool = false
    ) {
        self.id = id ?? bcp47Code
        self.bcp47Code = bcp47Code
        self.name = name
        self.localizedName = localizedName
        self.flagEmoji = flagEmoji
        self.isAutoDetect = isAutoDetect
    }
}

// MARK: - AppLanguage Presets

extension AppLanguage {
    /// Automatic language detection mode (source only).
    public static let autoDetect = AppLanguage(
        id: "auto",
        bcp47Code: "auto",
        name: "Deteksi Otomatis",
        localizedName: "Auto Detect",
        flagEmoji: "🌐",
        isAutoDetect: true
    )

    /// Bahasa Indonesia (default target language).
    public static let indonesian = AppLanguage(
        id: "id",
        bcp47Code: "id",
        name: "Bahasa Indonesia",
        localizedName: "Indonesian",
        flagEmoji: "🇮🇩"
    )

    /// Chinese (Mandarin, Simplified) - 简体中文.
    public static let simplifiedChinese = AppLanguage(
        id: "zh-Hans",
        bcp47Code: "zh-Hans",
        name: "Chinese (Mandarin, Simplified) - 中文",
        localizedName: "Chinese (Simplified)",
        flagEmoji: "🇨🇳"
    )

    /// Chinese (Mandarin, Traditional) - 繁體中文.
    public static let traditionalChinese = AppLanguage(
        id: "zh-Hant",
        bcp47Code: "zh-Hant",
        name: "Chinese (Mandarin, Traditional) - 繁體中文",
        localizedName: "Chinese (Traditional)",
        flagEmoji: "🇹🇼"
    )

    /// English.
    public static let english = AppLanguage(
        id: "en",
        bcp47Code: "en",
        name: "English",
        localizedName: "English",
        flagEmoji: "🇺🇸"
    )

    /// Japanese - 日本語.
    public static let japanese = AppLanguage(
        id: "ja",
        bcp47Code: "ja",
        name: "Japanese - 日本語",
        localizedName: "Japanese",
        flagEmoji: "🇯🇵"
    )

    /// Korean - 한국어.
    public static let korean = AppLanguage(
        id: "ko",
        bcp47Code: "ko",
        name: "Korean - 한국어",
        localizedName: "Korean",
        flagEmoji: "🇰🇷"
    )

    /// French - Français.
    public static let french = AppLanguage(
        id: "fr",
        bcp47Code: "fr",
        name: "French - Français",
        localizedName: "French",
        flagEmoji: "🇫🇷"
    )

    /// German - Deutsch.
    public static let german = AppLanguage(
        id: "de",
        bcp47Code: "de",
        name: "German - Deutsch",
        localizedName: "German",
        flagEmoji: "🇩🇪"
    )

    /// Spanish - Español.
    public static let spanish = AppLanguage(
        id: "es",
        bcp47Code: "es",
        name: "Spanish - Español",
        localizedName: "Spanish",
        flagEmoji: "🇪🇸"
    )

    /// Italian - Italiano.
    public static let italian = AppLanguage(
        id: "it",
        bcp47Code: "it",
        name: "Italian - Italiano",
        localizedName: "Italian",
        flagEmoji: "🇮🇹"
    )

    /// List of all concrete supported languages (excluding `.autoDetect`).
    public static let allSupportedLanguages: [AppLanguage] = [
        .indonesian,
        .simplifiedChinese,
        .traditionalChinese,
        .english,
        .japanese,
        .korean,
        .french,
        .german,
        .spanish,
        .italian
    ]

    /// Supported options for source language (including `.autoDetect`).
    public static let sourceLanguages: [AppLanguage] = [.autoDetect] + allSupportedLanguages

    /// Supported options for target language (concrete languages only).
    public static let targetLanguages: [AppLanguage] = allSupportedLanguages

    /// Finds the best matching `AppLanguage` for a given BCP-47 or ISO-639 language code.
    public static func from(code: String) -> AppLanguage? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return nil }

        if trimmed == "auto" {
            return .autoDetect
        }
        if trimmed.starts(with: "zh-hant") || trimmed == "zht" {
            return .traditionalChinese
        }
        if trimmed.starts(with: "zh") || trimmed == "chi" {
            return .simplifiedChinese
        }

        return allSupportedLanguages.first { language in
            let langCode = language.bcp47Code.lowercased()
            return langCode == trimmed || langCode.starts(with: trimmed) || trimmed.starts(with: langCode)
        }
    }

    /// Finds the best matching `AppLanguage` for a `Locale.Language`.
    public static func from(locale: Locale.Language) -> AppLanguage? {
        if let script = locale.script?.identifier, let code = locale.languageCode?.identifier {
            if let match = from(code: "\(code)-\(script)") {
                return match
            }
        }
        if let code = locale.languageCode?.identifier {
            return from(code: code)
        }
        return nil
    }
}

// MARK: - LanguagePair

/// Represents a directed source and target translation language pair.
public struct LanguagePair: Identifiable, Equatable, Hashable, Sendable {
    /// Unique identifier for the pair, e.g. "zh-Hans_id" or "auto_id".
    public let id: String

    /// The source language to be translated from.
    public var source: AppLanguage

    /// The target language to be translated to.
    public var target: AppLanguage

    /// Whether the pair relies on automatic source language detection.
    public var isAutoDetect: Bool {
        source.isAutoDetect
    }

    /// BCP-47 identifier for the source language (e.g. "auto", "zh-Hans", "en").
    public var sourceCode: String {
        source.bcp47Code
    }

    /// BCP-47 identifier for the target language (e.g. "id").
    public var targetCode: String {
        target.bcp47Code
    }

    /// Foundation `Locale.Language` for the source, or `nil` if auto-detect.
    public var sourceLocaleLanguage: Locale.Language? {
        source.localeLanguage
    }

    /// Foundation `Locale.Language` for the target.
    public var targetLocaleLanguage: Locale.Language {
        target.localeLanguage ?? Locale.Language(identifier: "id")
    }

    /// User-facing display name with flag emojis (e.g. "🇨🇳 Chinese (Mandarin, Simplified) - 中文 ➔ 🇮🇩 Bahasa Indonesia").
    public var displayName: String {
        "\(source.flagEmoji) \(source.name) ➔ \(target.flagEmoji) \(target.name)"
    }

    /// Compact display name (e.g. "Chinese (Simplified) → Indonesian").
    public var shortDisplayName: String {
        "\(source.localizedName) → \(target.localizedName)"
    }

    /// Creates a `LanguagePair`.
    public init(source: AppLanguage, target: AppLanguage) {
        self.id = "\(source.bcp47Code)_\(target.bcp47Code)"
        self.source = source
        self.target = target
    }

    /// Convenience initializer from language codes.
    public init(sourceCode: String, targetCode: String = "id") {
        let sourceLang = AppLanguage.from(code: sourceCode) ?? AppLanguage(
            bcp47Code: sourceCode,
            name: sourceCode,
            localizedName: sourceCode,
            flagEmoji: "🌐"
        )
        let targetLang = AppLanguage.from(code: targetCode) ?? .indonesian
        self.init(source: sourceLang, target: targetLang)
    }
}

// MARK: - LanguagePair Presets

extension LanguagePair {
    /// Auto-detect ➔ Bahasa Indonesia (default app mode).
    public static let autoToIndonesian = LanguagePair(
        source: .autoDetect,
        target: .indonesian
    )

    /// Chinese (Simplified) ➔ Bahasa Indonesia.
    public static let chineseToIndonesian = LanguagePair(
        source: .simplifiedChinese,
        target: .indonesian
    )

    /// English ➔ Bahasa Indonesia.
    public static let englishToIndonesian = LanguagePair(
        source: .english,
        target: .indonesian
    )

    /// Japanese ➔ Bahasa Indonesia.
    public static let japaneseToIndonesian = LanguagePair(
        source: .japanese,
        target: .indonesian
    )

    /// Korean ➔ Bahasa Indonesia.
    public static let koreanToIndonesian = LanguagePair(
        source: .korean,
        target: .indonesian
    )

    /// Chinese (Traditional) ➔ Bahasa Indonesia.
    public static let traditionalChineseToIndonesian = LanguagePair(
        source: .traditionalChinese,
        target: .indonesian
    )

    /// Curated preset language pairs for quick selection and onboarding.
    public static let presetPairs: [LanguagePair] = [
        .autoToIndonesian,
        .chineseToIndonesian,
        .englishToIndonesian,
        .japaneseToIndonesian,
        .koreanToIndonesian,
        .traditionalChineseToIndonesian
    ]

    /// Default language pair for initial app launch.
    public static let defaultPair = LanguagePair.autoToIndonesian
}
