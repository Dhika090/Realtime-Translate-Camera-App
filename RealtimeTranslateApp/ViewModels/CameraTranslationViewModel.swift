import Foundation
import Combine
import CoreGraphics
import CoreVideo
import SwiftUI
import AVFoundation

#if canImport(Translation)
import Translation
#endif

// MARK: - CameraTranslationViewModel

/// Central ViewModel orchestrating camera frame ingestion, throttled OCR processing,
/// temporal text tracking, automatic language detection, batch translation, and UI state.
///
/// Architecture & Concurrency:
/// - Isolated to `@MainActor` to ensure safe, deterministic UI updates.
/// - Ingests camera frames asynchronously from `CameraCaptureManager`.
/// - Throttles OCR inference to ~5–10 Hz using `OCRServiceProtocol`.
/// - Stabilizes text bounding boxes across frames using `BoxTracker`.
/// - Automatically detects dominant language via `LanguageDetectionService`.
/// - Dispatches batch translations via `TranslationServiceProtocol`.
/// - Coordinates freeze-frame locks, flashlight/torch toggles, and sheet presentations.
@MainActor
public final class CameraTranslationViewModel: ObservableObject {

    // MARK: - Published State

    /// Currently tracked and stabilized text blocks on screen.
    @Published public var trackedBlocks: [TrackedTextBlock] = []

    /// The text block currently inspected in the detail card sheet.
    @Published public var selectedBlock: TrackedTextBlock? = nil

    /// Active source translation language (.auto / .autoDetect by default).
    @Published public var sourceLanguage: AppLanguage = .auto

    /// Active target translation language (.indonesian by default).
    @Published public var targetLanguage: AppLanguage = .indonesian

    /// Dominant language detected in the current camera scene when in auto-detect mode.
    @Published public var detectedDominantLanguage: AppLanguage? = nil

    /// Whether the camera preview is currently frozen on a static snapshot.
    @Published public var isFrozen: Bool = false

    /// Whether the camera torch / flashlight is active.
    @Published public var isTorchOn: Bool = false

    /// Whether the pre-trip offline language onboarding sheet is presented.
    @Published public var showOnboardingSheet: Bool = false

    /// Whether the detail inspection card sheet is presented.
    @Published public var showDetailSheet: Bool = false

    /// Whether a background batch translation task is in flight.
    @Published public var isTranslating: Bool = false

    /// User-facing error message, or nil if healthy.
    @Published public var errorMessage: String? = nil

    // MARK: - Subsystem Dependencies

    /// Camera capture manager handling AVCaptureSession and video frames.
    public let cameraManager: CameraCaptureManager

    /// OCR recognition service with frame throttling and line clustering.
    public let ocrService: OCRServiceProtocol

    /// Translation service providing offline and on-demand batch translation.
    public let translationService: TranslationServiceProtocol

    /// Natural language recognizer detecting dominant languages.
    public let languageDetectionService: LanguageDetectionService

    /// Temporal tracker smoothing bounding boxes and preserving persistent IDs.
    public let boxTracker: BoxTracker

    // MARK: - Persistence Keys

    public static let sourceLanguageDefaultsKey = "com.app.realtimeTranslate.sourceLanguage"
    public static let targetLanguageDefaultsKey = "com.app.realtimeTranslate.targetLanguage"

    // MARK: - Internal Concurrency & Subscription State

    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var isProcessingFrame: Bool = false
    private var translationTask: Task<Void, Never>? = nil

    // MARK: - Initialization

    /// Creates a `CameraTranslationViewModel` with injectable services and persistent language preferences.
    ///
    /// - Parameters:
    ///   - cameraManager: Camera manager instance (defaults to new `CameraCaptureManager`).
    ///   - ocrService: OCR service (defaults to standard `OCRService`).
    ///   - translationService: Translation service (defaults to standard `TranslationService`).
    ///   - languageDetectionService: Dominant language detection service.
    ///   - boxTracker: Temporal bounding box tracker.
    ///   - sourceLanguage: Optional source language (defaults to stored UserDefaults or `.auto`).
    ///   - targetLanguage: Optional target language (defaults to stored UserDefaults or `.indonesian`).
    ///   - userDefaults: UserDefaults instance for preference persistence (defaults to `.standard`).
    public init(
        cameraManager: CameraCaptureManager = CameraCaptureManager(),
        ocrService: OCRServiceProtocol = OCRService(),
        translationService: TranslationServiceProtocol = TranslationService(),
        languageDetectionService: LanguageDetectionService = LanguageDetectionService(),
        boxTracker: BoxTracker = BoxTracker(),
        sourceLanguage: AppLanguage? = nil,
        targetLanguage: AppLanguage? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.cameraManager = cameraManager
        self.ocrService = ocrService
        self.translationService = translationService
        self.languageDetectionService = languageDetectionService
        self.boxTracker = boxTracker
        self.userDefaults = userDefaults

        // Source Language resolution: explicit argument -> stored UserDefaults -> default (.auto)
        if let explicitSource = sourceLanguage {
            self.sourceLanguage = explicitSource
        } else if let savedCode = userDefaults.string(forKey: Self.sourceLanguageDefaultsKey),
                  let loaded = AppLanguage.from(code: savedCode) {
            self.sourceLanguage = loaded
        } else {
            self.sourceLanguage = .auto
        }

        // Target Language resolution: explicit argument -> stored UserDefaults -> default (.indonesian)
        if let explicitTarget = targetLanguage {
            self.targetLanguage = explicitTarget
        } else if let savedCode = userDefaults.string(forKey: Self.targetLanguageDefaultsKey),
                  let loaded = AppLanguage.from(code: savedCode) {
            self.targetLanguage = loaded
        } else {
            self.targetLanguage = .indonesian
        }

        self.isFrozen = cameraManager.isFrozen
        self.isTorchOn = cameraManager.isTorchOn

        setupSubscriptions()
    }

    // MARK: - Subscriptions Setup

    private func setupSubscriptions() {
        // Sync torch state from camera manager
        cameraManager.$isTorchOn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] torchState in
                self?.isTorchOn = torchState
            }
            .store(in: &cancellables)

        // Sync freeze state from camera manager
        cameraManager.$isFrozen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frozenState in
                self?.isFrozen = frozenState
            }
            .store(in: &cancellables)

        // Sync camera errors
        cameraManager.$sessionError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                }
            }
            .store(in: &cancellables)

        // Stream video frames into OCR processing pipeline
        // Background frame filtering before dispatching to the main thread (avoids 60 FPS main-thread wakeups)
        cameraManager.framePublisher
            .filter { [weak self] _ in
                self?.ocrService.shouldProcessFrame() == true
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pixelBuffer in
                self?.processFrame(pixelBuffer)
            }
            .store(in: &cancellables)
    }

    // MARK: - Frame Processing Pipeline

    /// Ingests a camera frame and executes the OCR, tracking, language detection, and translation pipeline.
    ///
    /// Heavy Vision OCR and box tracking are offloaded to background threads (`Task.detached`),
    /// keeping `@MainActor` free for smooth 60 FPS UI rendering.
    ///
    /// - Parameter pixelBuffer: Raw CVPixelBuffer from the camera stream.
    public func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Drop frames while frozen or if another OCR cycle is actively processing
        guard !isFrozen else { return }
        guard !isProcessingFrame else { return }
        guard ocrService.shouldProcessFrame() else { return }

        isProcessingFrame = true

        Task.detached(priority: .userInitiated) { [weak self, ocrService, boxTracker] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isProcessingFrame = false
                }
            }

            do {
                // 1. Vision OCR processing on background thread
                let detectedBlocks = try await ocrService.process(pixelBuffer: pixelBuffer)

                // 2. Temporal BoxTracker association & coordinate smoothing
                let updatedTracked = boxTracker.track(blocks: detectedBlocks)

                // 3. Update UI published state & trigger translations on MainActor
                await MainActor.run { [weak self] in
                    guard let self = self else { return }

                    // Dominant Language Detection (if in auto-detect mode)
                    if self.sourceLanguage.isAutoDetect {
                        self.detectDominantLanguage(from: updatedTracked)
                    }

                    // 4. Update UI published state
                    self.trackedBlocks = updatedTracked
                    self.syncSelectedBlock(with: updatedTracked)

                    // 5. Asynchronous Translation Dispatch for untranslated blocks
                    Task { [weak self] in
                        await self?.dispatchTranslationsIfNeeded(for: updatedTracked)
                    }
                }

            } catch OCRError.frameThrottled {
                // Normal throttled frame drop, no error reporting needed
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "OCR processing error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Dominant Language Detection

    private func detectDominantLanguage(from blocks: [TrackedTextBlock]) {
        guard !blocks.isEmpty else { return }

        // Combine non-empty merged strings from recognized blocks
        let sampleText = blocks
            .map(\.mergedText)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")

        guard !sampleText.isEmpty else { return }

        if let detected = languageDetectionService.detectAppLanguage(text: sampleText) {
            if self.detectedDominantLanguage != detected {
                self.detectedDominantLanguage = detected
            }
        }
    }

    // MARK: - Batch Translation Dispatch

    /// Dispatches batch translation for untranslated text blocks.
    public func dispatchTranslationsIfNeeded(for blocks: [TrackedTextBlock]) async {
        // Find blocks that lack translation
        let pendingBlocks = blocks.filter { block in
            (block.translatedText == nil || block.translatedText?.isEmpty == true) &&
            !block.mergedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !pendingBlocks.isEmpty else { return }

        // Determine effective source locale language
        let effectiveSource: Locale.Language?
        if sourceLanguage.isAutoDetect {
            effectiveSource = detectedDominantLanguage?.localeLanguage
        } else {
            effectiveSource = sourceLanguage.localeLanguage
        }

        // Effective target locale language
        let effectiveTarget = targetLanguage.localeLanguage ?? Locale.Language(identifier: "id")

        isTranslating = true
        defer { isTranslating = false }

        let textsToTranslate = pendingBlocks.map(\.mergedText)

        do {
            let translations = try await translationService.translate(
                texts: textsToTranslate,
                source: effectiveSource,
                target: effectiveTarget
            )

            guard translations.count == pendingBlocks.count else { return }

            let sourceCode = effectiveSource?.languageCode?.identifier ?? sourceLanguage.bcp47Code

            // Update box tracker with translations
            for (index, block) in pendingBlocks.enumerated() {
                let translated = translations[index]
                self.boxTracker.updateTranslation(
                    for: block.id,
                    translatedText: translated,
                    sourceLanguage: sourceCode
                )
            }

            // Sync tracked blocks to UI
            self.trackedBlocks = self.boxTracker.trackedBlocks
            self.syncSelectedBlock(with: self.trackedBlocks)

        } catch {
            self.errorMessage = "Translation error: \(error.localizedDescription)"
        }
    }

    // MARK: - Selection & Detail Inspection

    /// Selects a text block and presents the inspection detail card sheet.
    public func selectBlock(_ block: TrackedTextBlock) {
        self.selectedBlock = block
        self.showDetailSheet = true
    }

    /// Selects a text block from a `DetectedTextBlock`.
    public func selectBlock(_ detectedBlock: DetectedTextBlock) {
        let tracked = TrackedTextBlock(detectedBlock: detectedBlock)
        selectBlock(tracked)
    }

    /// Clears the active selection and dismisses the detail sheet.
    public func clearSelection() {
        self.selectedBlock = nil
        self.showDetailSheet = false
    }

    private func syncSelectedBlock(with blocks: [TrackedTextBlock]) {
        guard let currentSelected = selectedBlock else { return }
        if let updated = blocks.first(where: { $0.id == currentSelected.id }) {
            self.selectedBlock = updated
        }
    }

    // MARK: - Language Configuration & Re-translation

    /// Sets the source translation language and persists to UserDefaults.
    public func setSourceLanguage(_ language: AppLanguage) {
        guard sourceLanguage != language else { return }
        sourceLanguage = language
        userDefaults.set(language.bcp47Code, forKey: Self.sourceLanguageDefaultsKey)

        if !language.isAutoDetect {
            detectedDominantLanguage = nil
        }

        retranslateAll()
    }

    /// Sets the target translation language and persists to UserDefaults.
    public func setTargetLanguage(_ language: AppLanguage) {
        guard targetLanguage != language else { return }
        targetLanguage = language
        userDefaults.set(language.bcp47Code, forKey: Self.targetLanguageDefaultsKey)

        retranslateAll()
    }

    /// Swaps source and target languages if source is not auto-detect and persists to UserDefaults.
    public func swapLanguages() {
        if sourceLanguage.isAutoDetect {
            guard let detected = detectedDominantLanguage else { return }
            let oldTarget = targetLanguage
            sourceLanguage = oldTarget
            targetLanguage = detected
            detectedDominantLanguage = nil
        } else {
            let oldSource = sourceLanguage
            sourceLanguage = targetLanguage
            targetLanguage = oldSource
        }

        userDefaults.set(sourceLanguage.bcp47Code, forKey: Self.sourceLanguageDefaultsKey)
        userDefaults.set(targetLanguage.bcp47Code, forKey: Self.targetLanguageDefaultsKey)

        retranslateAll()
    }

    /// Clears existing translations and triggers a fresh batch translation for all active tracked blocks.
    public func retranslateAll() {
        let currentBlocks = boxTracker.trackedBlocks
        guard !currentBlocks.isEmpty else { return }

        // Clear translations in tracker
        for block in currentBlocks {
            boxTracker.updateTranslation(for: block.id, translatedText: "")
        }

        self.trackedBlocks = boxTracker.trackedBlocks

        Task { [weak self] in
            guard let self = self else { return }
            await self.dispatchTranslationsIfNeeded(for: self.trackedBlocks)
        }
    }

    // MARK: - Camera Controls & Freeze Frame

    /// Starts the camera capture session.
    public func startCamera() async {
        await cameraManager.startSession()
        self.isFrozen = cameraManager.isFrozen
        self.isTorchOn = cameraManager.isTorchOn
    }

    /// Stops the camera capture session and turns off torch.
    public func stopCamera() async {
        await cameraManager.stopSession()
        self.isTorchOn = false
    }

    /// Toggles freeze frame mode on or off.
    public func toggleFreeze() {
        cameraManager.toggleFreezeFrame()
        self.isFrozen = cameraManager.isFrozen

        // When freezing, run a high-fidelity un-throttled OCR pass on the frozen buffer in background
        if self.isFrozen, let buffer = cameraManager.frozenPixelBuffer {
            Task.detached(priority: .userInitiated) { [weak self, ocrService, boxTracker] in
                do {
                    let blocks = try await ocrService.process(
                        pixelBuffer: buffer,
                        orientation: .up,
                        ignoreThrottling: true
                    )
                    let tracked = boxTracker.track(blocks: blocks)
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        if self.sourceLanguage.isAutoDetect {
                            self.detectDominantLanguage(from: tracked)
                        }
                        self.trackedBlocks = tracked
                        self.syncSelectedBlock(with: tracked)
                        Task { [weak self] in
                            await self?.dispatchTranslationsIfNeeded(for: tracked)
                        }
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "Freeze frame OCR failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    /// Freezes the current camera frame.
    public func freeze() {
        guard !isFrozen else { return }
        toggleFreeze()
    }

    /// Unfreezes the camera feed and resumes real-time capture.
    public func unfreeze() {
        guard isFrozen else { return }
        toggleFreeze()
    }

    /// Toggles the flashlight / torch.
    public func toggleTorch() {
        self.isTorchOn = cameraManager.toggleTorch()
    }

    /// Clears all detected and tracked text blocks and resets error state.
    public func clearTrackedBlocks() {
        boxTracker.reset()
        trackedBlocks.removeAll()
        selectedBlock = nil
        errorMessage = nil
    }

    // MARK: - Native Apple Translation Session Hook

    #if canImport(Translation)
    /// Registers an Apple `TranslationSession` provided by SwiftUI's `.translationTask`.
    @available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
    public func setTranslationSession(_ session: TranslationSession) {
        if let concreteService = translationService as? TranslationService {
            concreteService.setTranslationSession(session)
        }
    }
    #endif
}
