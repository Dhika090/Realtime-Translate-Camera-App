import SwiftUI

#if canImport(Translation)
import Translation
#endif

// MARK: - Pack Download Status

/// Represents the download status of an offline language pack.
public enum PackDownloadStatus: String, Sendable, Equatable, Hashable {
    case installed = "installed"
    case supported = "supported"
    case downloading = "downloading"
    case unsupported = "unsupported"

    public var title: String {
        switch self {
        case .installed:
            return "Siap Digunakan"
        case .supported:
            return "Tersedia"
        case .downloading:
            return "Mengunduh..."
        case .unsupported:
            return "Tidak Didukung"
        }
    }

    public var color: Color {
        switch self {
        case .installed:
            return .green
        case .supported:
            return .blue
        case .downloading:
            return .orange
        case .unsupported:
            return .secondary
        }
    }

    public var iconName: String {
        switch self {
        case .installed:
            return "checkmark.circle.fill"
        case .supported:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.triangle.2.circlepath"
        case .unsupported:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - Offline Language Pack Item

/// Model representing a downloadable offline language pair package.
public struct OfflineLanguagePack: Identifiable, Equatable, Sendable {
    public let id: String
    public let pair: LanguagePair
    public let sizeDescription: String
    public var status: PackDownloadStatus

    public init(
        id: String? = nil,
        pair: LanguagePair,
        sizeDescription: String = "~35-50 MB",
        status: PackDownloadStatus = .supported
    ) {
        self.id = id ?? pair.id
        self.pair = pair
        self.sizeDescription = sizeDescription
        self.status = status
    }

    /// Curated list of popular language packs for Indonesian travelers.
    public static let recommendedPacks: [OfflineLanguagePack] = [
        OfflineLanguagePack(
            pair: .chineseToIndonesian,
            sizeDescription: "~42 MB",
            status: .supported
        ),
        OfflineLanguagePack(
            pair: .englishToIndonesian,
            sizeDescription: "~35 MB",
            status: .installed
        ),
        OfflineLanguagePack(
            pair: .japaneseToIndonesian,
            sizeDescription: "~48 MB",
            status: .supported
        ),
        OfflineLanguagePack(
            pair: .koreanToIndonesian,
            sizeDescription: "~45 MB",
            status: .supported
        ),
        OfflineLanguagePack(
            pair: LanguagePair(source: .spanish, target: .indonesian),
            sizeDescription: "~38 MB",
            status: .supported
        )
    ]
}

// MARK: - OnboardingLanguageSheet

/// Pre-trip offline language download guide sheet.
///
/// Designed to educate travelers to download required language models before embarking,
/// ensuring 100% offline real-time camera translation without cellular or roaming data.
public struct OnboardingLanguageSheet: View {

    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @State private var packs: [OfflineLanguagePack]
    @State private var isCheckingAvailability: Bool = false
    @State private var activeDownloadId: String? = nil

    /// Optional dismiss callback.
    public let onDismiss: (() -> Void)?

    /// Optional download trigger callback.
    public let onDownloadRequested: ((OfflineLanguagePack) -> Void)?

    // MARK: - Initialization

    /// Initializes with custom or default recommended packs.
    public init(
        initialPacks: [OfflineLanguagePack] = OfflineLanguagePack.recommendedPacks,
        onDownloadRequested: ((OfflineLanguagePack) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self._packs = State(initialValue: initialPacks)
        self.onDownloadRequested = onDownloadRequested
        self.onDismiss = onDismiss
    }

    /// Convenience initializer binding to `CameraTranslationViewModel`.
    public init(
        viewModel: CameraTranslationViewModel,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            initialPacks: OfflineLanguagePack.recommendedPacks,
            onDownloadRequested: { pack in
                Task {
                    _ = await viewModel.translationService.checkAvailability(
                        from: pack.pair.sourceLocaleLanguage,
                        to: pack.pair.targetLocaleLanguage
                    )
                }
            },
            onDismiss: onDismiss
        )
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    packsListSection
                    tipsCardSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        handleDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Tutup panduan offline")
                }
            }
            .safeAreaInset(edge: .bottom) {
                primaryActionButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 8)

            Text("Persiapan Bepergian (Offline Mode)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text("Unduh paket bahasa sebelum bepergian agar kamera penerjemah dapat berjalan 100% offline tanpa kuota internet.")
                .font(.system(size: 14, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Packs List Section

    private var packsListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Paket Bahasa Populer")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("Apple Translation")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
            }

            VStack(spacing: 10) {
                ForEach(packs) { pack in
                    languagePackCard(pack)
                }
            }
        }
    }

    // MARK: - Language Pack Card

    private func languagePackCard(_ pack: OfflineLanguagePack) -> some View {
        HStack(spacing: 14) {
            // Language flags & name
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pack.pair.source.flagEmoji)
                        .font(.system(size: 20))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(pack.pair.target.flagEmoji)
                        .font(.system(size: 20))

                    Text(pack.pair.source.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Label(pack.sizeDescription, systemImage: "internaldrive")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("➔ \(pack.pair.target.name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status or Action Button
            packActionButton(for: pack)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(pack.status == .installed ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Pack Action Button

    @ViewBuilder
    private func packActionButton(for pack: OfflineLanguagePack) -> some View {
        switch pack.status {
        case .installed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Terunduh")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.12))
            .clipShape(Capsule())

        case .downloading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Mengunduh")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())

        case .supported:
            Button {
                startDownload(for: pack)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Unduh")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.blue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        case .unsupported:
            Text("Tidak Didukung")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
    }

    // MARK: - Tips Section

    private var tipsCardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tahukah Anda?", systemImage: "lightbulb.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.orange)

            Text("Model penerjemahan Apple tersimpan secara privat di perangkat Anda. Begitu terunduh, penerjemahan kamera tidak memerlukan sambungan Wi-Fi atau data seluler sama sekali.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Primary Action Button

    private var primaryActionButton: some View {
        Button {
            handleDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Mulai Menggunakan Kamera")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
        }
    }

    // MARK: - Actions

    private func startDownload(for pack: OfflineLanguagePack) {
        guard let index = packs.firstIndex(where: { $0.id == pack.id }) else { return }

        packs[index].status = .downloading
        activeDownloadId = pack.id
        onDownloadRequested?(pack)

        // Simulate or track completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let idx = self.packs.firstIndex(where: { $0.id == pack.id }) {
                self.packs[idx].status = .installed
                if self.activeDownloadId == pack.id {
                    self.activeDownloadId = nil
                }
            }
        }
    }

    private func handleDismiss() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}
