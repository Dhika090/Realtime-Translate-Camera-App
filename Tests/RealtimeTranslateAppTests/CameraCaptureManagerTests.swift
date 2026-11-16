import XCTest
import AVFoundation
import CoreVideo
import CoreGraphics
import CoreImage
import Combine
import SwiftUI
@testable import RealtimeTranslateApp

// MARK: - Mocks & Test Doubles

final class MockTorchController: TorchControllerProtocol, @unchecked Sendable {
    var hasTorch: Bool
    var isTorchAvailable: Bool
    var torchMode: AVCaptureDevice.TorchMode
    var setTorchModeCallCount: Int = 0
    var shouldThrowError: Bool = false

    init(
        hasTorch: Bool = true,
        isTorchAvailable: Bool = true,
        torchMode: AVCaptureDevice.TorchMode = .off
    ) {
        self.hasTorch = hasTorch
        self.isTorchAvailable = isTorchAvailable
        self.torchMode = torchMode
    }

    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) throws {
        setTorchModeCallCount += 1
        if shouldThrowError {
            throw CameraCaptureError.torchNotAvailable
        }
        torchMode = mode
    }
}

final class MockCameraAuthorizationProvider: CameraAuthorizationProviderProtocol, @unchecked Sendable {
    var status: AVAuthorizationStatus
    var grantedOnRequest: Bool
    var requestAccessCallCount: Int = 0

    init(status: AVAuthorizationStatus = .authorized, grantedOnRequest: Bool = true) {
        self.status = status
        self.grantedOnRequest = grantedOnRequest
    }

    func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        status
    }

    func requestAccess(for mediaType: AVMediaType) async -> Bool {
        requestAccessCallCount += 1
        status = grantedOnRequest ? .authorized : .denied
        return grantedOnRequest
    }
}

// MARK: - Test PixelBuffer Helpers

private func createTestPixelBuffer(width: Int = 64, height: Int = 64) -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )
    assert(status == kCVReturnSuccess && pixelBuffer != nil, "Failed to create test pixel buffer")
    return pixelBuffer!
}

// MARK: - CameraCaptureManagerTests

final class CameraCaptureManagerTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - 1. Initial State Tests

    func testInitialStateWithDefaultMock() {
        let authProvider = MockCameraAuthorizationProvider(status: .authorized)
        let torch = MockTorchController()
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: torch,
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        XCTAssertFalse(manager.isRunning)
        XCTAssertFalse(manager.isTorchOn)
        XCTAssertFalse(manager.isFrozen)
        XCTAssertNil(manager.frozenImage)
        XCTAssertNil(manager.frozenPixelBuffer)
        XCTAssertEqual(manager.authorizationStatus, .authorized)
        XCTAssertNil(manager.sessionError)
    }

    func testInitialStateWithNotDeterminedPermission() {
        let authProvider = MockCameraAuthorizationProvider(status: .notDetermined)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        XCTAssertEqual(manager.authorizationStatus, .notDetermined)
    }

    // MARK: - 2. Authorization Tests

    func testCheckAuthorizationWhenAlreadyAuthorizedDoesNotRequestAgain() async {
        let authProvider = MockCameraAuthorizationProvider(status: .authorized)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        let result = await manager.checkAuthorization()

        XCTAssertTrue(result)
        XCTAssertEqual(authProvider.requestAccessCallCount, 0)
        XCTAssertEqual(manager.authorizationStatus, .authorized)
    }

    func testCheckAuthorizationWhenNotDeterminedRequestsAndGrants() async {
        let authProvider = MockCameraAuthorizationProvider(status: .notDetermined, grantedOnRequest: true)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        let result = await manager.checkAuthorization()

        XCTAssertTrue(result)
        XCTAssertEqual(authProvider.requestAccessCallCount, 1)
        XCTAssertEqual(manager.authorizationStatus, .authorized)
    }

    func testCheckAuthorizationWhenNotDeterminedRequestsAndDenies() async {
        let authProvider = MockCameraAuthorizationProvider(status: .notDetermined, grantedOnRequest: false)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        let result = await manager.checkAuthorization()

        XCTAssertFalse(result)
        XCTAssertEqual(authProvider.requestAccessCallCount, 1)
        XCTAssertEqual(manager.authorizationStatus, .denied)
    }

    func testCheckAuthorizationWhenDeniedReturnsFalseImmediately() async {
        let authProvider = MockCameraAuthorizationProvider(status: .denied)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        let result = await manager.checkAuthorization()

        XCTAssertFalse(result)
        XCTAssertEqual(authProvider.requestAccessCallCount, 0)
        XCTAssertEqual(manager.authorizationStatus, .denied)
    }

    func testExplicitRequestAuthorization() async {
        let authProvider = MockCameraAuthorizationProvider(status: .notDetermined, grantedOnRequest: true)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        let granted = await manager.requestAuthorization()

        XCTAssertTrue(granted)
        XCTAssertEqual(authProvider.requestAccessCallCount, 1)
        XCTAssertEqual(manager.authorizationStatus, .authorized)
    }

    // MARK: - 3. Freeze & Unfreeze State Tests

    func testFreezeFrameCachesLatestPixelBufferAndGeneratesCGImage() {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let buffer1 = createTestPixelBuffer(width: 48, height: 48)
        manager.processCapturedPixelBuffer(buffer1)

        manager.freezeFrame()

        XCTAssertTrue(manager.isFrozen)
        XCTAssertNotNil(manager.frozenPixelBuffer)
        XCTAssertNotNil(manager.frozenImage)
        if let image = manager.frozenImage {
            XCTAssertEqual(image.width, 48)
            XCTAssertEqual(image.height, 48)
        }
    }

    func testIncomingFramesDroppedWhileFrozen() {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let buffer1 = createTestPixelBuffer(width: 32, height: 32)
        let buffer2 = createTestPixelBuffer(width: 64, height: 64)

        var emittedFrames: [CVPixelBuffer] = []
        manager.onFrameCaptured = { buffer in
            emittedFrames.append(buffer)
        }

        // Deliver initial frame before freeze
        manager.processCapturedPixelBuffer(buffer1)
        XCTAssertEqual(emittedFrames.count, 1)

        // Freeze
        manager.freezeFrame()
        XCTAssertTrue(manager.isFrozen)

        // Deliver second frame during freeze
        manager.processCapturedPixelBuffer(buffer2)

        // Second frame must be dropped
        XCTAssertEqual(emittedFrames.count, 1)
        XCTAssertEqual(manager.frozenImage?.width, 32)
    }

    func testUnfreezeFrameClearsCacheAndResumesFrameEmission() {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let buffer1 = createTestPixelBuffer(width: 32, height: 32)
        let buffer2 = createTestPixelBuffer(width: 64, height: 64)

        var emittedFrames: [CVPixelBuffer] = []
        manager.onFrameCaptured = { buffer in
            emittedFrames.append(buffer)
        }

        manager.processCapturedPixelBuffer(buffer1)
        manager.freezeFrame()
        XCTAssertTrue(manager.isFrozen)
        XCTAssertNotNil(manager.frozenPixelBuffer)
        XCTAssertNotNil(manager.frozenImage)

        // Unfreeze
        manager.unfreezeFrame()
        XCTAssertFalse(manager.isFrozen)
        XCTAssertNil(manager.frozenPixelBuffer)
        XCTAssertNil(manager.frozenImage)

        // Deliver frame after unfreeze
        manager.processCapturedPixelBuffer(buffer2)
        XCTAssertEqual(emittedFrames.count, 2)
    }

    func testRedundantFreezeAndUnfreezeAreSafeNoOps() {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        // Unfreezing while already unfrozen
        manager.unfreezeFrame()
        XCTAssertFalse(manager.isFrozen)

        let buffer = createTestPixelBuffer(width: 16, height: 16)
        manager.processCapturedPixelBuffer(buffer)

        // Freezing
        manager.freezeFrame()
        XCTAssertTrue(manager.isFrozen)

        // Redundant freeze
        manager.freezeFrame()
        XCTAssertTrue(manager.isFrozen)
    }

    func testFreezeWithoutPriorFramesSetsFrozenWithNilImages() {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        manager.freezeFrame()

        XCTAssertTrue(manager.isFrozen)
        XCTAssertNil(manager.frozenPixelBuffer)
        XCTAssertNil(manager.frozenImage)

        manager.unfreezeFrame()
        XCTAssertFalse(manager.isFrozen)
    }

    func testToggleFreezeFrame() {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let buffer = createTestPixelBuffer(width: 24, height: 24)
        manager.processCapturedPixelBuffer(buffer)

        // Toggle 1: Freeze
        manager.toggleFreezeFrame()
        XCTAssertTrue(manager.isFrozen)
        XCTAssertNotNil(manager.frozenImage)

        // Toggle 2: Unfreeze
        manager.toggleFreezeFrame()
        XCTAssertFalse(manager.isFrozen)
        XCTAssertNil(manager.frozenImage)
    }

    // MARK: - 4. Torch Control Tests

    func testTorchToggleCycleWhenAvailable() {
        let torch = MockTorchController(hasTorch: true, isTorchAvailable: true, torchMode: .off)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: torch,
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        // 1st toggle: turn ON
        let firstToggle = manager.toggleTorch()
        XCTAssertTrue(firstToggle)
        XCTAssertTrue(manager.isTorchOn)
        XCTAssertEqual(torch.torchMode, .on)
        XCTAssertEqual(torch.setTorchModeCallCount, 1)

        // 2nd toggle: turn OFF
        let secondToggle = manager.toggleTorch()
        XCTAssertFalse(secondToggle)
        XCTAssertFalse(manager.isTorchOn)
        XCTAssertEqual(torch.torchMode, .off)
        XCTAssertEqual(torch.setTorchModeCallCount, 2)
    }

    func testTorchToggleWhenNoTorchPresent() {
        let torch = MockTorchController(hasTorch: false, isTorchAvailable: false, torchMode: .off)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: torch,
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let result = manager.toggleTorch()
        XCTAssertFalse(result)
        XCTAssertFalse(manager.isTorchOn)
        XCTAssertEqual(torch.setTorchModeCallCount, 0)
    }

    func testTorchToggleWhenTorchUnavailable() {
        let torch = MockTorchController(hasTorch: true, isTorchAvailable: false, torchMode: .off)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: torch,
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let result = manager.toggleTorch()
        XCTAssertFalse(result)
        XCTAssertFalse(manager.isTorchOn)
        XCTAssertEqual(torch.setTorchModeCallCount, 0)
    }

    func testTorchToggleWhenControllerThrowsError() {
        let torch = MockTorchController(hasTorch: true, isTorchAvailable: true, torchMode: .off)
        torch.shouldThrowError = true

        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: torch,
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let result = manager.toggleTorch()
        XCTAssertFalse(result)
        XCTAssertFalse(manager.isTorchOn)
        XCTAssertEqual(torch.setTorchModeCallCount, 1)
    }

    func testStopSessionTurnsOffActiveTorch() async {
        let torch = MockTorchController(hasTorch: true, isTorchAvailable: true, torchMode: .off)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: torch,
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        manager.toggleTorch()
        XCTAssertTrue(manager.isTorchOn)
        XCTAssertEqual(torch.torchMode, .on)

        await manager.stopSession()

        XCTAssertFalse(manager.isTorchOn)
        XCTAssertEqual(torch.torchMode, .off)
    }

    // MARK: - 5. Frame Delivery & Streaming Tests

    func testCombineFramePublisherReceivesFrames() {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        var receivedBuffers: [CVPixelBuffer] = []
        let expectation = XCTestExpectation(description: "Combine frame received")

        manager.framePublisher
            .sink { buffer in
                receivedBuffers.append(buffer)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let buffer = createTestPixelBuffer(width: 32, height: 32)
        manager.processCapturedPixelBuffer(buffer)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedBuffers.count, 1)
    }

    func testAsyncStreamYieldsCapturedFrames() async {
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: MockCameraAuthorizationProvider(),
            cameraDeviceProvider: { nil }
        )

        let stream = manager.makeFrameStream()
        let buffer1 = createTestPixelBuffer(width: 16, height: 16)

        let streamTask = Task { () -> [CVPixelBuffer] in
            var collected: [CVPixelBuffer] = []
            for await frame in stream {
                collected.append(frame)
                if collected.count >= 1 {
                    break
                }
            }
            return collected
        }

        // Small yield to let task begin awaiting
        await Task.yield()
        manager.processCapturedPixelBuffer(buffer1)

        let collected = await streamTask.value
        XCTAssertEqual(collected.count, 1)
    }

    // MARK: - 6. PixelBuffer to CGImage Conversion Tests

    func testPixelBufferConversionToCGImage() {
        let buffer = createTestPixelBuffer(width: 64, height: 64)
        let cgImage = CameraCaptureManager.convert(pixelBuffer: buffer)

        XCTAssertNotNil(cgImage)
        XCTAssertEqual(cgImage?.width, 64)
        XCTAssertEqual(cgImage?.height, 64)
    }

    func testPixelBufferToCGImageExtension() {
        let buffer = createTestPixelBuffer(width: 40, height: 40)
        let cgImage = buffer.toCGImage()

        XCTAssertNotNil(cgImage)
        XCTAssertEqual(cgImage?.width, 40)
        XCTAssertEqual(cgImage?.height, 40)
    }

    // MARK: - 7. Error & Permission Denied Session Handling

    func testStartSessionWithPermissionDeniedSetsError() async {
        let authProvider = MockCameraAuthorizationProvider(status: .denied)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        await manager.startSession()

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.sessionError, .permissionDenied)
    }

    func testStartSessionDeviceNotAvailableSetsError() async {
        let authProvider = MockCameraAuthorizationProvider(status: .authorized)
        let manager = CameraCaptureManager(
            session: AVCaptureSession(),
            torchController: MockTorchController(),
            authorizationProvider: authProvider,
            cameraDeviceProvider: { nil }
        )

        await manager.startSession()

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.sessionError, .deviceNotAvailable)
    }

    func testCameraCaptureErrorDescriptions() {
        let errors: [CameraCaptureError] = [
            .deviceNotAvailable,
            .inputNotSupported,
            .outputNotSupported,
            .torchNotAvailable,
            .sessionConfigurationFailed,
            .permissionDenied
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - 8. Preview View Container UIView Tests

    func testVideoPreviewContainerUIViewConfiguration() {
        let view = VideoPreviewContainerUIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        XCTAssertTrue(view.layer is AVCaptureVideoPreviewLayer)
        XCTAssertEqual(view.previewLayer.videoGravity, .resizeAspectFill)

        // Trigger layout pass
        view.layoutSubviews()
        XCTAssertEqual(view.previewLayer.frame, CGRect(x: 0, y: 0, width: 320, height: 480))
    }

    func testCameraPreviewViewConvenienceInitializer() {
        let session = AVCaptureSession()
        let preview = CameraPreviewView(session: session, videoGravity: .resizeAspect)

        XCTAssertEqual(preview.videoGravity, .resizeAspect)
        XCTAssertTrue(preview.captureManager.session === session)
    }
}
