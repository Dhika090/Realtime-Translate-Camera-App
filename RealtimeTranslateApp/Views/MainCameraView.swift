import SwiftUI
import AVFoundation

#if canImport(Translation)
import Translation
#endif

// MARK: - MainCameraView

/// The primary full-screen camera translation interface.
///
/// Component Architecture:
/// - **Background Layer**: `CameraPreviewView` rendering live camera feed or frozen snapshot.
/// - **AR Overlay Layer**: `AROverlayCanvas` positioning interactive frosted-glass badges above detected text.
/// - **Top Floating Navigation Bar**: Source and target language selector menus, language swap, and offline pack onboarding trigger.
/// - **Bottom Floating Control Bar**: Torch/flash toggle, freeze-frame lock button, and clear/reset button.
/// - **Status Overlays**: Frame frozen indicator, batch translation progress pill, and non-intrusive error toasts.
/// - **Detail Inspection Sheet**: Presents `DetailCardSheet` when an AR text badge is tapped.
/// - **Pre-Trip Onboarding Sheet**: Presents `OnboardingLanguageSheet` for offline language pack downloads.
@MainActor
public struct MainCameraView: View {

    // MARK: - View Model

    @StateObject public var viewModel: CameraTranslationViewModel

    #if canImport(Translation)
    @State private var translationConfig: TranslationSession.Configuration?
    #endif

    // MARK: - Initialization

    /// Creates a `MainCameraView` with an existing or new `CameraTranslationViewModel`.
    public init(viewModel: CameraTranslationViewModel = CameraTranslationViewModel()) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Layer 1: Full-Screen Camera Video Preview & Freeze Snapshot
            CameraPreviewView(captureManager: viewModel.cameraManager)
                .ignoresSafeArea()

            // Layer 2: AR Overlay Canvas with Positioned Text Badges
            AROverlayCanvas(
                trackedBlocks: viewModel.trackedBlocks,
                selectedBlockId: viewModel.selectedBlock?.id,
                targetLanguageCode: viewModel.targetLanguage.bcp47Code,
                onSelectBlock: { block in
                    viewModel.selectBlock(block)
                }
            )
            .ignoresSafeArea()

            // Layer 3: Floating UI Controls & Overlays
            VStack {
                topNavigationBar
                    .padding(.top, 8)

                statusIndicators
                    .padding(.top, 6)

                Spacer()

                bottomControlBar
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .task {
            await viewModel.startCamera()
            updateTranslationConfiguration()
        }
        .onDisappear {
            Task {
                await viewModel.stopCamera()
            }
        }
        .sheet(isPresented: $viewModel.showDetailSheet) {
            if let selected = viewModel.selectedBlock {
                DetailCardSheet(
                    block: selected,
                    targetLanguage: viewModel.targetLanguage,
                    fallbackSourceLanguage: viewModel.sourceLanguage.isAutoDetect
                        ? (viewModel.detectedDominantLanguage ?? .auto)
                        : viewModel.sourceLanguage,
                    onDismiss: {
                        viewModel.clearSelection()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $viewModel.showOnboardingSheet) {
            OnboardingLanguageSheet(
                viewModel: viewModel,
                onDismiss: {
                    viewModel.showOnboardingSheet = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        #if canImport(Translation)
        .modifier(TranslationTaskModifier(config: translationConfig) { session in
            if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
                viewModel.setTranslationSession(session)
            }
        })
        #endif
        .onChange(of: viewModel.sourceLanguage) { _, _ in
            updateTranslationConfiguration()
        }
        .onChange(of: viewModel.targetLanguage) { _, _ in
            updateTranslationConfiguration()
        }
        .onChange(of: viewModel.detectedDominantLanguage) { _, _ in
            updateTranslationConfiguration()
        }
    }

    // MARK: - Top Floating Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            // Source Language Dropdown Menu
            sourceLanguageMenu

            // Direction Arrow / Swap Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.swapLanguages()
                }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .accessibilityLabel("Tukar bahasa")

            // Target Language Dropdown Menu
            targetLanguageMenu

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.3))

            // Pre-Trip Offline Pack Download Button
            Button {
                viewModel.showOnboardingSheet = true
            } label: {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
            }
            .accessibilityLabel("Panduan paket bahasa offline")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
    }

    // MARK: - Source Language Menu

    private var sourceLanguageMenu: some View {
        Menu {
            ForEach(AppLanguage.sourceLanguages) { lang in
                Button {
                    viewModel.setSourceLanguage(lang)
                } label: {
                    HStack {
                        Text("\(lang.flagEmoji) \(lang.name)")
                        if viewModel.sourceLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(viewModel.sourceLanguage.flagEmoji)
                    .font(.system(size: 15))

                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.sourceLanguage.localizedName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if viewModel.sourceLanguage.isAutoDetect, let detected = viewModel.detectedDominantLanguage {
                        Text(detected.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.cyan)
                            .lineLimit(1)
                    }
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .accessibilityLabel("Pilih bahasa sumber: \(viewModel.sourceLanguage.name)")
    }

    // MARK: - Target Language Menu

    private var targetLanguageMenu: some View {
        Menu {
            ForEach(AppLanguage.targetLanguages) { lang in
                Button {
                    viewModel.setTargetLanguage(lang)
                } label: {
                    HStack {
                        Text("\(lang.flagEmoji) \(lang.name)")
                        if viewModel.targetLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(viewModel.targetLanguage.flagEmoji)
                    .font(.system(size: 15))

                Text(viewModel.targetLanguage.localizedName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .accessibilityLabel("Pilih bahasa tujuan: \(viewModel.targetLanguage.name)")
    }

    // MARK: - Status Indicators

    private var statusIndicators: some View {
        VStack(spacing: 6) {
            // Frozen State Notification Pill
            if viewModel.isFrozen {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Frame Terkunci (Ketuk Tombol Play untuk Lanjut)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.blue.opacity(0.92))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: Color.blue.opacity(0.4), radius: 6, x: 0, y: 2)
                .transition(.scale.combined(with: .opacity))
            }

            // Batch Translating Progress Pill
            if viewModel.isTranslating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                    Text("Menerjemahkan teks...")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .transition(.opacity)
            }

            // Error Banner (if any)
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Button {
                        viewModel.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.7))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFrozen)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTranslating)
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
    }

    // MARK: - Bottom Floating Control Bar

    private var bottomControlBar: some View {
        HStack(spacing: 36) {
            // Flashlight / Torch Toggle Button
            Button {
                viewModel.toggleTorch()
            } label: {
                Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(viewModel.isTorchOn ? .yellow : .white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
            }
            .accessibilityLabel(viewModel.isTorchOn ? "Matikan lampu sorot" : "Nyalakan lampu sorot")

            // Main Freeze / Resume Frame Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    viewModel.toggleFreeze()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel.isFrozen ? Color.blue : Color.white.opacity(0.22))
                        .frame(width: 72, height: 72)

                    Circle()
                        .stroke(viewModel.isFrozen ? Color.white : Color.blue, lineWidth: 3.5)
                        .frame(width: 63, height: 63)

                    Image(systemName: viewModel.isFrozen ? "play.fill" : "pause.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(
                    color: viewModel.isFrozen ? Color.blue.opacity(0.55) : Color.black.opacity(0.35),
                    radius: 10,
                    x: 0,
                    y: 4
                )
            }
            .accessibilityLabel(viewModel.isFrozen ? "Lanjutkan video langsung" : "Kunci gambar untuk membaca")

            // Clear / Reset Tracked Blocks Button
            Button {
                viewModel.clearTrackedBlocks()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
            }
            .accessibilityLabel("Bersihkan teks terdeteksi")
        }
    }

    // MARK: - Native Translation Configuration Helper

    private func updateTranslationConfiguration() {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
            let targetLocale = viewModel.targetLanguage.localeLanguage ?? Locale.Language(identifier: "id")
            let sourceLocale: Locale.Language?
            if viewModel.sourceLanguage.isAutoDetect {
                sourceLocale = viewModel.detectedDominantLanguage?.localeLanguage
            } else {
                sourceLocale = viewModel.sourceLanguage.localeLanguage
            }
            self.translationConfig = TranslationSession.Configuration(source: sourceLocale, target: targetLocale)
        }
        #endif
    }
}

// MARK: - Translation Task ViewModifier

#if canImport(Translation)
@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
private struct TranslationTaskModifier: ViewModifier {
    let config: TranslationSession.Configuration?
    let onSessionAvailable: @MainActor @Sendable (TranslationSession) -> Void

    func body(content: Content) -> some View {
        content.translationTask(config) { session in
            await onSessionAvailable(session)
        }
    }
}
#endif
