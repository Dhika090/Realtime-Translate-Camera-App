import SwiftUI

// MARK: - App Entry Point

/// Main application entry point for the Real-Time Camera Translation iOS App.
///
/// Designed with pure native Apple frameworks (iOS 18+):
/// - AVFoundation for 60 FPS real-time camera capture.
/// - Vision for throttled on-device OCR text recognition.
/// - NaturalLanguage for dominant language identification.
/// - Apple Translation Framework for on-device offline machine translation.
/// - SwiftUI for the frosted-glass AR camera overlay and inspection views.
@main
struct RealtimeTranslateApp: App {

    @StateObject private var viewModel = CameraTranslationViewModel()

    var body: some Scene {
        WindowGroup {
            MainCameraView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
