import SwiftUI
import CoreGraphics

// MARK: - AROverlayCanvas

/// SwiftUI container view overlaying the live camera preview.
///
/// Maps detected text blocks to screen positions with aspect-fill correction,
/// renders interactive frosted-glass `ARTextBadgeView`s, and handles tap selection.
public struct AROverlayCanvas: View {

    // MARK: - Properties

    /// Active tracked text blocks to render.
    public let trackedBlocks: [TrackedTextBlock]

    /// Unique identifier of the currently inspected/selected block.
    public let selectedBlockId: UUID?

    /// Aspect ratio (width / height) of the underlying camera stream. Defaults to 9:16 portrait (0.5625).
    public let videoAspectRatio: CGFloat

    /// Optional target language code override (e.g., "ID").
    public let targetLanguageCode: String?

    /// Closure invoked when the user selects a block.
    public let onSelectBlock: (TrackedTextBlock) -> Void

    // MARK: - Initialization

    /// Creates an `AROverlayCanvas` with `TrackedTextBlock` inputs.
    public init(
        trackedBlocks: [TrackedTextBlock],
        selectedBlockId: UUID? = nil,
        videoAspectRatio: CGFloat = 9.0 / 16.0,
        targetLanguageCode: String? = nil,
        onSelectBlock: @escaping (TrackedTextBlock) -> Void
    ) {
        self.trackedBlocks = trackedBlocks
        self.selectedBlockId = selectedBlockId
        self.videoAspectRatio = videoAspectRatio
        self.targetLanguageCode = targetLanguageCode
        self.onSelectBlock = onSelectBlock
    }

    /// Convenience initializer accepting `DetectedTextBlock`s.
    public init(
        detectedBlocks: [DetectedTextBlock],
        selectedBlockId: UUID? = nil,
        videoAspectRatio: CGFloat = 9.0 / 16.0,
        targetLanguageCode: String? = nil,
        onSelectDetectedBlock: @escaping (DetectedTextBlock) -> Void
    ) {
        self.trackedBlocks = detectedBlocks.map { TrackedTextBlock(detectedBlock: $0) }
        self.selectedBlockId = selectedBlockId
        self.videoAspectRatio = videoAspectRatio
        self.targetLanguageCode = targetLanguageCode
        self.onSelectBlock = { tracked in
            onSelectDetectedBlock(tracked.toDetectedTextBlock())
        }
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(trackedBlocks) { block in
                    let screenRect = computeScreenRect(for: block, in: geometry.size)
                    let isSelected = (selectedBlockId == block.id)

                    ARTextBadgeView(
                        block: block,
                        isSelected: isSelected,
                        targetLanguageCode: targetLanguageCode,
                        onTap: {
                            onSelectBlock(block)
                        }
                    )
                    .frame(
                        minWidth: min(max(screenRect.width, 60), geometry.size.width * 0.8),
                        maxWidth: max(screenRect.width + 16, 120),
                        minHeight: max(screenRect.height, 28)
                    )
                    .position(x: screenRect.midX, y: screenRect.midY)
                    .id(block.id)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.15), value: trackedBlocks)
        }
    }

    // MARK: - Coordinate Calculation Helper

    /// Computes the destination screen rectangle for a given text block within the container view size.
    ///
    /// Detects whether `block.boundingBox` is normalized (Vision space: 0...1, origin bottom-left)
    /// or already transformed to screen points, applying `CoordinateTransformer` when needed.
    public func computeScreenRect(for block: TrackedTextBlock, in viewSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }

        let box = block.boundingBox
        guard !box.isNull, !box.isEmpty else {
            return .zero
        }

        // Check if the bounding box is in normalized coordinates (<= 1.05)
        let isNormalized = (box.origin.x <= 1.05 && box.origin.y <= 1.05 &&
                            box.size.width <= 1.05 && box.size.height <= 1.05)

        if isNormalized {
            return CoordinateTransformer.convert(
                visionRect: box,
                viewSize: viewSize,
                videoAspectRatio: videoAspectRatio
            )
        }

        return box
    }
}
