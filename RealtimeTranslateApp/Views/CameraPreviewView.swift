import SwiftUI
import AVFoundation
import UIKit

// MARK: - CameraPreviewView

/// A SwiftUI view that renders real-time camera capture using `AVCaptureVideoPreviewLayer`,
/// and displays a snapshot overlay when the capture feed is frozen.
public struct CameraPreviewView: View {

    // MARK: - Properties

    /// The camera capture manager governing session state and frozen snapshots.
    @ObservedObject public var captureManager: CameraCaptureManager

    /// Scaling behavior of the preview layer within its bounds. Defaults to `.resizeAspectFill`.
    public var videoGravity: AVLayerVideoGravity

    // MARK: - Initialization

    /// Initializes a preview view with a live `CameraCaptureManager`.
    /// - Parameters:
    ///   - captureManager: The capture manager managing the active `AVCaptureSession`.
    ///   - videoGravity: Scaling rule for camera frames (defaults to `.resizeAspectFill`).
    public init(
        captureManager: CameraCaptureManager,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) {
        self.captureManager = captureManager
        self.videoGravity = videoGravity
    }

    /// Convenience initializer when only the `AVCaptureSession` is available.
    /// - Parameters:
    ///   - session: The raw `AVCaptureSession` to display.
    ///   - videoGravity: Scaling rule for camera frames (defaults to `.resizeAspectFill`).
    public init(
        session: AVCaptureSession,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) {
        self.init(
            captureManager: CameraCaptureManager(session: session),
            videoGravity: videoGravity
        )
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background fill
                Color.black
                    .edgesIgnoringSafeArea(.all)

                // Live AVFoundation preview layer
                VideoPreviewLayerRepresentable(
                    session: captureManager.session,
                    videoGravity: videoGravity
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()

                // Frozen frame snapshot overlay
                if captureManager.isFrozen, let frozenImage = captureManager.frozenImage {
                    Image(decorative: frozenImage, scale: 1.0, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - VideoPreviewLayerRepresentable

/// A `UIViewRepresentable` bridging `AVCaptureVideoPreviewLayer` into SwiftUI.
public struct VideoPreviewLayerRepresentable: UIViewRepresentable {

    /// The capture session to render.
    public let session: AVCaptureSession

    /// Video gravity preset for aspect fill / fit.
    public var videoGravity: AVLayerVideoGravity

    public init(
        session: AVCaptureSession,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill
    ) {
        self.session = session
        self.videoGravity = videoGravity
    }

    public func makeUIView(context: Context) -> VideoPreviewContainerUIView {
        let view = VideoPreviewContainerUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = videoGravity
        return view
    }

    public func updateUIView(_ uiView: VideoPreviewContainerUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.previewLayer.videoGravity = videoGravity
        uiView.updateOrientation()
    }
}

// MARK: - VideoPreviewContainerUIView

/// UIKit container view backed by `AVCaptureVideoPreviewLayer`.
public final class VideoPreviewContainerUIView: UIView {

    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    /// Strongly-typed accessor for the backing preview layer.
    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        updateOrientation()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            updateOrientation()
        }
    }

    /// Synchronizes preview layer video orientation with the window interface orientation.
    public func updateOrientation() {
        guard let connection = previewLayer.connection, connection.isVideoOrientationSupported else {
            return
        }

        let interfaceOrientation: UIInterfaceOrientation
        if let windowScene = window?.windowScene {
            interfaceOrientation = windowScene.interfaceOrientation
        } else {
            interfaceOrientation = .portrait
        }

        let targetVideoOrientation = videoOrientation(from: interfaceOrientation)
        if connection.videoOrientation != targetVideoOrientation {
            connection.videoOrientation = targetVideoOrientation
        }
    }

    /// Maps `UIInterfaceOrientation` to `AVCaptureVideoOrientation`.
    private func videoOrientation(from interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }
}
