import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CoreImage
import Combine
import SwiftUI

// MARK: - Camera Capture Error

/// Errors that can occur during camera discovery, configuration, or control.
public enum CameraCaptureError: LocalizedError, Equatable, Sendable {
    case deviceNotAvailable
    case inputNotSupported
    case outputNotSupported
    case torchNotAvailable
    case sessionConfigurationFailed
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .deviceNotAvailable:
            return "Camera device is not available on this system."
        case .inputNotSupported:
            return "Unable to add video device input to capture session."
        case .outputNotSupported:
            return "Unable to add video data output to capture session."
        case .torchNotAvailable:
            return "Flashlight / torch is not available or supported on this device."
        case .sessionConfigurationFailed:
            return "Failed to configure AVCaptureSession."
        case .permissionDenied:
            return "Camera capture permission was denied by the user."
        }
    }
}

// MARK: - Protocols for Device Abstraction & Testability

/// Abstraction for camera flashlight / torch control to facilitate testing without physical hardware.
public protocol TorchControllerProtocol: AnyObject, Sendable {
    var hasTorch: Bool { get }
    var isTorchAvailable: Bool { get }
    var torchMode: AVCaptureDevice.TorchMode { get }
    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws
}

/// Default torch controller operating on an underlying `AVCaptureDevice`.
public final class DefaultTorchController: TorchControllerProtocol, @unchecked Sendable {
    private let deviceProvider: @Sendable () -> AVCaptureDevice?

    public init(deviceProvider: @escaping @Sendable () -> AVCaptureDevice? = {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }) {
        self.deviceProvider = deviceProvider
    }

    public init(device: AVCaptureDevice) {
        self.deviceProvider = { device }
    }

    public var hasTorch: Bool {
        deviceProvider()?.hasTorch ?? false
    }

    public var isTorchAvailable: Bool {
        deviceProvider()?.isTorchAvailable ?? false
    }

    public var torchMode: AVCaptureDevice.TorchMode {
        deviceProvider()?.torchMode ?? .off
    }

    public func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        guard let device = deviceProvider() else {
            throw CameraCaptureError.deviceNotAvailable
        }
        guard device.hasTorch && device.isTorchAvailable else {
            throw CameraCaptureError.torchNotAvailable
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.torchMode = mode
    }
}

/// Abstraction for camera permission queries and requests.
public protocol CameraAuthorizationProviderProtocol: Sendable {
    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus
    func requestAccess(for mediaType: AVMediaType) async -> Bool
}

/// Default camera authorization provider using `AVCaptureDevice`.
public final class DefaultCameraAuthorizationProvider: CameraAuthorizationProviderProtocol {
    public init() {}

    public func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: mediaType)
    }

    public func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await AVCaptureDevice.requestAccess(for: mediaType)
    }
}

// MARK: - CameraCaptureManager

/// Manages the real-time `AVCaptureSession`, frame delivery, freeze-frame caching, and torch controls.
///
/// Designed to feed downstream OCR pipelines (`OCRService`) at 60 FPS while supporting instant freeze-frame
/// snapshot inspection and thread-safe control from SwiftUI views.
public final class CameraCaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    // MARK: - Published Properties

    /// Whether the capture session is actively running.
    @Published public private(set) var isRunning: Bool = false

    /// Whether the flashlight / torch is currently turned on.
    @Published public private(set) var isTorchOn: Bool = false

    /// Whether the camera feed is currently frozen on a static frame.
    @Published public private(set) var isFrozen: Bool = false

    /// The static CGImage snapshot captured at the moment the feed was frozen.
    @Published public private(set) var frozenImage: CGImage? = nil

    /// The static CVPixelBuffer captured at the moment the feed was frozen.
    @Published public private(set) var frozenPixelBuffer: CVPixelBuffer? = nil

    /// The current camera authorization status.
    @Published public private(set) var authorizationStatus: AVAuthorizationStatus

    /// Last error encountered during session setup or capture.
    @Published public private(set) var sessionError: CameraCaptureError? = nil

    // MARK: - Capture Infrastructure

    /// The underlying `AVCaptureSession`.
    public let session: AVCaptureSession

    /// Dedicated serial queue for video data output sample buffer delegate callbacks.
    private let videoDataQueue: DispatchQueue

    /// Dedicated serial queue for session start / stop operations.
    private let sessionQueue: DispatchQueue

    /// Device controller for torch operations.
    public let torchController: TorchControllerProtocol

    /// Provider for camera permissions.
    private let authorizationProvider: CameraAuthorizationProviderProtocol

    /// Closure providing the video capture device.
    private let cameraDeviceProvider: @Sendable () -> AVCaptureDevice?

    /// Active video device input attached to the session.
    private var activeDeviceInput: AVCaptureDeviceInput?

    /// Video data output attached to the session.
    private var videoDataOutput: AVCaptureVideoDataOutput?

    /// Flag indicating whether the capture session has been configured.
    private var isSessionConfigured: Bool = false

    // MARK: - Frame Streaming & Freeze State Synchronization

    /// Lock protecting freeze state and cached pixel buffer.
    private let stateLock = NSLock()

    /// Internal boolean tracking freeze state on the background queue.
    private var internalIsFrozen: Bool = false

    /// Most recently received pixel buffer from the live stream.
    private var internalLastPixelBuffer: CVPixelBuffer?

    /// Combine publisher broadcasting live video frames.
    public let frameSubject = PassthroughSubject<CVPixelBuffer, Never>()

    /// Erased publisher for frame consumption.
    public var framePublisher: AnyPublisher<CVPixelBuffer, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    /// Closure callback invoked on every captured video frame.
    public var onFrameCaptured: (@Sendable (CVPixelBuffer) -> Void)?

    /// Lock protecting active AsyncStream continuations.
    private let streamLock = NSLock()

    /// Active AsyncStream continuations for frame distribution.
    private var streamContinuations: [UUID: AsyncStream<CVPixelBuffer>.Continuation] = [:]

    // MARK: - Initialization

    /// Initializes a new `CameraCaptureManager`.
    /// - Parameters:
    ///   - session: Custom `AVCaptureSession` (defaults to a new instance).
    ///   - torchController: Optional torch controller (defaults to `DefaultTorchController`).
    ///   - authorizationProvider: Provider for camera authorization checks (defaults to `DefaultCameraAuthorizationProvider`).
    ///   - cameraDeviceProvider: Factory for finding camera devices (defaults to default back wide-angle camera).
    public init(
        session: AVCaptureSession = AVCaptureSession(),
        torchController: TorchControllerProtocol? = nil,
        authorizationProvider: CameraAuthorizationProviderProtocol = DefaultCameraAuthorizationProvider(),
        cameraDeviceProvider: @escaping @Sendable () -> AVCaptureDevice? = {
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
    ) {
        self.session = session
        self.videoDataQueue = DispatchQueue(
            label: "com.app.camera.videoDataQueue",
            qos: .userInitiated
        )
        self.sessionQueue = DispatchQueue(
            label: "com.app.camera.sessionQueue",
            qos: .userInitiated
        )
        self.cameraDeviceProvider = cameraDeviceProvider
        self.torchController = torchController ?? DefaultTorchController(deviceProvider: cameraDeviceProvider)
        self.authorizationProvider = authorizationProvider
        self.authorizationStatus = authorizationProvider.authorizationStatus(for: .video)
        super.init()
    }

    deinit {
        streamLock.lock()
        for continuation in streamContinuations.values {
            continuation.finish()
        }
        streamContinuations.removeAll()
        streamLock.unlock()
    }

    // MARK: - Permission Handling

    /// Checks the current authorization status, requesting access if not yet determined.
    /// - Returns: `true` if authorized, `false` otherwise.
    @discardableResult
    public func checkAuthorization() async -> Bool {
        let currentStatus = authorizationProvider.authorizationStatus(for: .video)
        switch currentStatus {
        case .authorized:
            updateMain { self.authorizationStatus = .authorized }
            return true
        case .notDetermined:
            let granted = await authorizationProvider.requestAccess(for: .video)
            let newStatus = authorizationProvider.authorizationStatus(for: .video)
            updateMain { self.authorizationStatus = newStatus }
            return granted
        case .denied, .restricted:
            updateMain { self.authorizationStatus = currentStatus }
            return false
        @unknown default:
            updateMain { self.authorizationStatus = currentStatus }
            return false
        }
    }

    /// Requests camera authorization explicitly.
    /// - Returns: `true` if granted, `false` otherwise.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        let granted = await authorizationProvider.requestAccess(for: .video)
        let newStatus = authorizationProvider.authorizationStatus(for: .video)
        updateMain { self.authorizationStatus = newStatus }
        return granted
    }

    // MARK: - Session Configuration & Lifecycle

    /// Configures session inputs, outputs, and presets.
    public func configureSessionIfNeeded() throws {
        guard !isSessionConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Configure optimal session preset for OCR text clarity
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        // Add back camera input
        guard let camera = cameraDeviceProvider() else {
            throw CameraCaptureError.deviceNotAvailable
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(videoInput) else {
            throw CameraCaptureError.inputNotSupported
        }
        session.addInput(videoInput)
        self.activeDeviceInput = videoInput

        // Add video data output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoDataQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CameraCaptureError.outputNotSupported
        }
        session.addOutput(videoOutput)
        self.videoDataOutput = videoOutput

        // Configure connection orientation to portrait
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }

        isSessionConfigured = true
    }

    /// Starts the capture session on a dedicated background thread.
    public func startSession() async {
        let authorized = await checkAuthorization()
        guard authorized else {
            updateMain {
                self.sessionError = .permissionDenied
            }
            return
        }

        do {
            try configureSessionIfNeeded()
        } catch let error as CameraCaptureError {
            updateMain {
                self.sessionError = error
            }
            return
        } catch {
            updateMain {
                self.sessionError = .sessionConfigurationFailed
            }
            return
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.updateMain {
                    self.isRunning = self.session.isRunning
                    self.sessionError = nil
                }
                continuation.resume()
            }
        }
    }

    /// Stops the capture session and switches off torch if active.
    public func stopSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                if self.isTorchOn {
                    try? self.torchController.setTorchMode(.off)
                    self.updateMain {
                        self.isTorchOn = false
                    }
                }
                self.updateMain {
                    self.isRunning = false
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Torch Control

    /// Toggles the back flashlight / torch between `.on` and `.off`.
    /// - Returns: `true` if torch is now active, `false` otherwise.
    @discardableResult
    public func toggleTorch() -> Bool {
        guard torchController.hasTorch && torchController.isTorchAvailable else {
            updateMain {
                self.isTorchOn = false
            }
            return false
        }

        let targetMode: AVCaptureDevice.TorchMode = isTorchOn ? .off : .on
        do {
            try torchController.setTorchMode(targetMode)
            let newState = (targetMode == .on)
            updateMain {
                self.isTorchOn = newState
            }
            return newState
        } catch {
            updateMain {
                self.isTorchOn = false
            }
            return false
        }
    }

    // MARK: - Freeze Frame Controls

    /// Atomically locks the camera stream on the most recent frame and populates `frozenImage` and `frozenPixelBuffer`.
    public func freezeFrame() {
        stateLock.lock()
        guard !internalIsFrozen else {
            stateLock.unlock()
            return
        }
        internalIsFrozen = true
        let cachedBuffer = internalLastPixelBuffer
        stateLock.unlock()

        let image = cachedBuffer.flatMap { CameraCaptureManager.convert(pixelBuffer: $0) }

        updateMain {
            self.isFrozen = true
            self.frozenPixelBuffer = cachedBuffer
            self.frozenImage = image
        }
    }

    /// Resumes live camera video streaming, clearing frozen frame caches.
    public func unfreezeFrame() {
        stateLock.lock()
        guard internalIsFrozen else {
            stateLock.unlock()
            return
        }
        internalIsFrozen = false
        stateLock.unlock()

        updateMain {
            self.isFrozen = false
            self.frozenPixelBuffer = nil
            self.frozenImage = nil
        }
    }

    /// Toggles freeze frame mode on or off.
    public func toggleFreezeFrame() {
        stateLock.lock()
        let currentlyFrozen = internalIsFrozen
        stateLock.unlock()

        if currentlyFrozen {
            unfreezeFrame()
        } else {
            freezeFrame()
        }
    }

    // MARK: - Frame Delivery & Delegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processCapturedSampleBuffer(sampleBuffer)
    }

    /// Processes an incoming CMSampleBuffer, extracting its CVPixelBuffer.
    public func processCapturedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        processCapturedPixelBuffer(pixelBuffer)
    }

    /// Processes an incoming CVPixelBuffer, enforcing freeze gate and dispatching to consumers.
    public func processCapturedPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        stateLock.lock()
        if internalIsFrozen {
            stateLock.unlock()
            return
        }
        internalLastPixelBuffer = pixelBuffer
        stateLock.unlock()

        // 1. Invoke closure callback
        onFrameCaptured?(pixelBuffer)

        // 2. Publish on Combine subject
        frameSubject.send(pixelBuffer)

        // 3. Distribute to active AsyncStream continuations
        streamLock.lock()
        let continuations = Array(streamContinuations.values)
        streamLock.unlock()

        for continuation in continuations {
            continuation.yield(pixelBuffer)
        }
    }

    /// Creates an `AsyncStream` that receives video frames as they arrive from the camera.
    public func makeFrameStream() -> AsyncStream<CVPixelBuffer> {
        AsyncStream { continuation in
            let id = UUID()
            self.streamLock.lock()
            self.streamContinuations[id] = continuation
            self.streamLock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.streamLock.lock()
                self.streamContinuations.removeValue(forKey: id)
                self.streamLock.unlock()
            }
        }
    }

    // MARK: - Static Utilities

    /// Converts a `CVPixelBuffer` into a `CGImage` using CoreImage.
    /// - Parameter pixelBuffer: The raw camera pixel buffer.
    /// - Returns: A standard `CGImage`, or `nil` if conversion fails.
    public static func convert(pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    // MARK: - Private Helpers

    /// Dispatches state changes to the main thread immediately if already on main, or asynchronously.
    private func updateMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - CVPixelBuffer Extension

extension CVPixelBuffer {
    /// Convenience helper to convert the pixel buffer to a `CGImage`.
    public func toCGImage() -> CGImage? {
        CameraCaptureManager.convert(pixelBuffer: self)
    }
}
