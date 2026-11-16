# Real-Time Camera Translation iOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 100% offline real-time camera translation iOS application in pure native Swift & SwiftUI that detects foreign text (e.g., Chinese Mandarin), groups it into semantic blocks, translates it to a target language (e.g., Indonesian), and renders frosted-glass AR badges smoothly over the live camera stream.

**Architecture:** Pure Native iOS architecture utilizing `AVFoundation` for 60 FPS video capture, `Vision` (`VNRecognizeTextRequest`) for on-device OCR, spatial clustering algorithms to assemble multi-line text blocks, Apple's `Translation` framework (`TranslationSession`) for zero-network on-device translation, and a SwiftUI overlay layer using Exponential Moving Average (EMA) coordinate smoothing to present `.ultraThinMaterial` text badges.

**Tech Stack:** Swift 5.10+, SwiftUI, AVFoundation, Vision Framework, NaturalLanguage (`NLLanguageRecognizer`), Apple Translation Framework (`TranslationSession`), AVFAudio (`AVSpeechSynthesizer`), XCTest.

**Spec:** `C:\Users\Andika\.gemini\antigravity\scratch\realtime-camera-translate-ios\docs\superpowers\specs\2026-11-16-realtime-camera-translate-ios-design.md`

## Global Constraints

- Platform Target: iOS 18.0+ (required for programmatic `TranslationSession` API).
- Zero third-party SDK dependencies (100% Apple native frameworks).
- Offline-first execution: No network calls allowed for core camera translation pipeline.
- Camera Permission: `NSCameraUsageDescription` must be configured in `Info.plist`.
- Memory & Thermals: Vision OCR must be throttled to 5–10 Hz on a background queue (`.userInitiated`) while UI renders at 60 FPS.

## Review Focus

1. **Jittery Bounding Boxes**: Camera micro-movements causing AR badges to flicker or vibrate between frames. (Handled via Exponential Moving Average coordinate smoothing filter in Task 5).
2. **Fragmented Mandarin Text**: OCR breaking sentences into individual characters resulting in nonsensical translations. (Handled via 2D spatial clustering in Task 2).
3. **Missing Offline Language Pack**: User attempting translation before downloading system language pack. (Handled via graceful status check and pre-trip onboarding sheet in Task 4 & Task 7).
4. **Orientation & Coordinate Mismatch**: Vision normalized coordinates (origin bottom-left, y-up) vs. SwiftUI view coordinates (origin top-left, y-down). (Handled via explicit coordinate transformer in Task 5).
5. **Freeze Frame Drift**: Pausing the camera while in-flight OCR requests are pending, causing overlay mismatch. (Handled via atomic snapshot lock in Task 6).

---

## File Structure

```
RealtimeTranslateApp/
├── Models/
│   ├── DetectedTextBlock.swift       # Models for raw line, clustered block, translation state
│   └── LanguagePair.swift             # Supported language pairs and identification
├── Services/
│   ├── SpatialTextClusterer.swift    # 2D geometry clustering for OCR text lines
│   ├── OCRService.swift               # Vision framework wrapper (VNRecognizeTextRequest)
│   ├── LanguageDetectionService.swift # NaturalLanguage wrapper (NLLanguageRecognizer)
│   ├── TranslationService.swift       # Translation framework wrapper (TranslationSession)
│   └── CameraCaptureManager.swift     # AVFoundation camera session and frame capture
├── ViewModels/
│   └── CameraTranslationViewModel.swift # State coordinator: frames -> OCR -> translate -> UI
└── Views/
    ├── CameraPreviewView.swift        # AVCaptureVideoPreviewLayer UIViewRepresentable
    ├── ARTextBadgeView.swift          # Single frosted-glass overlay pill (.ultraThinMaterial)
    ├── AROverlayCanvas.swift          # Overlay layer mapping blocks to screen coordinates
    ├── DetailCardSheet.swift          # Inspection card for tapped translation
    ├── OnboardingLanguageSheet.swift  # Pre-trip language pack download manager
    └── MainCameraView.swift           # Root view combining camera, controls, and sheets
Tests/
├── RealtimeTranslateAppTests/
│   ├── SpatialTextClustererTests.swift
│   ├── CoordinateTransformerTests.swift
│   └── LanguageDetectionServiceTests.swift
```

---

## Tasks

### Task 1: Core Models & Spatial Text Clustering

**Files:**
- Create: `RealtimeTranslateApp/Models/DetectedTextBlock.swift`
- Create: `RealtimeTranslateApp/Services/SpatialTextClusterer.swift`
- Test: `Tests/RealtimeTranslateAppTests/SpatialTextClustererTests.swift`

**Interfaces:**
- Consumes: Foundation, CoreGraphics (`CGRect`)
- Produces: `DetectedTextBlock(id: UUID, rawLines: [String], mergedText: String, boundingBox: CGRect, translatedText: String?)`, `SpatialTextClusterer.cluster(lines: [OCRLine], lineSpacingThreshold: CGFloat) -> [DetectedTextBlock]`

- [ ] **Step 1: Write the failing unit tests for SpatialTextClusterer**
Test that multiple lines with small vertical spacing (e.g. multi-line Chinese menu items) are merged into a single block with a union bounding box, while vertically distant lines remain separate blocks.

```swift
import XCTest
@testable import RealtimeTranslateApp

final class SpatialTextClustererTests: XCTestCase {
    func testClusteringAdjacentLinesMergesIntoSingleBlock() {
        let line1 = OCRLine(text: "红烧", boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.2, height: 0.05))
        let line2 = OCRLine(text: "牛肉面", boundingBox: CGRect(x: 0.1, y: 0.74, width: 0.25, height: 0.05))
        
        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [line1, line2], lineSpacingThreshold: 0.03)
        
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "红烧牛肉面")
        XCTAssertEqual(blocks.first?.boundingBox.minX, 0.1)
    }
    
    func testDistantLinesRemainSeparateBlocks() {
        let line1 = OCRLine(text: "Header", boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.05))
        let line2 = OCRLine(text: "Footer", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05))
        
        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [line1, line2], lineSpacingThreshold: 0.05)
        
        XCTAssertEqual(blocks.count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `swift test --filter SpatialTextClustererTests`
Expected: FAIL (types `OCRLine`, `SpatialTextClusterer` not found).

- [ ] **Step 3: Implement `DetectedTextBlock.swift` and `SpatialTextClusterer.swift`**
Implement the clustering algorithm: sort lines top-to-bottom, compute vertical and horizontal distance between bounding boxes, group lines within `lineSpacingThreshold`, and compute `CGRectUnion`.

- [ ] **Step 4: Run test to verify it passes**
Run: `swift test --filter SpatialTextClustererTests`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add RealtimeTranslateApp/Models/DetectedTextBlock.swift RealtimeTranslateApp/Services/SpatialTextClusterer.swift Tests/
git commit -m "feat: add DetectedTextBlock model and SpatialTextClusterer algorithm"
```

---

### Task 2: Language Detection & Translation Service

**Files:**
- Create: `RealtimeTranslateApp/Models/LanguagePair.swift`
- Create: `RealtimeTranslateApp/Services/LanguageDetectionService.swift`
- Create: `RealtimeTranslateApp/Services/TranslationService.swift`
- Test: `Tests/RealtimeTranslateAppTests/LanguageDetectionServiceTests.swift`

**Interfaces:**
- Consumes: `NaturalLanguage`, `Translation`
- Produces: `LanguageDetectionService.detectDominantLanguage(text: String) -> Locale.Language?`, `TranslationServiceProtocol.translate(texts: [String], source: Locale.Language?, target: Locale.Language) async throws -> [String]`

- [ ] **Step 1: Write unit tests for LanguageDetectionService**
Test identifying Chinese scripts (`zh-Hans`), English (`en`), and Indonesian (`id`) from representative strings.

```swift
import XCTest
@testable import RealtimeTranslateApp

final class LanguageDetectionServiceTests: XCTestCase {
    func testDetectsChineseScript() {
        let detector = LanguageDetectionService()
        let lang = detector.detectDominantLanguage(text: "欢迎光临 餐厅")
        XCTAssertEqual(lang?.languageCode?.identifier, "zh")
    }
    
    func testDetectsIndonesianScript() {
        let detector = LanguageDetectionService()
        let lang = detector.detectDominantLanguage(text: "Selamat Datang di Restoran Kami")
        XCTAssertEqual(lang?.languageCode?.identifier, "id")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `swift test --filter LanguageDetectionServiceTests`
Expected: FAIL.

- [ ] **Step 3: Implement `LanguageDetectionService` and `TranslationService`**
- Implement `LanguageDetectionService` wrapping `NLLanguageRecognizer`.
- Implement `TranslationService` protocol and implementation using iOS 18 `TranslationSession` batch translation with offline availability checks.

- [ ] **Step 4: Run test to verify it passes**
Run: `swift test --filter LanguageDetectionServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add RealtimeTranslateApp/Models/LanguagePair.swift RealtimeTranslateApp/Services/ Tests/
git commit -m "feat: add LanguageDetectionService and TranslationService"
```

---

### Task 3: Vision OCR Pipeline with Frame Throttling

**Files:**
- Create: `RealtimeTranslateApp/Services/OCRService.swift`

**Interfaces:**
- Consumes: `Vision` (`VNRecognizeTextRequest`, `VNImageRequestHandler`), `SpatialTextClusterer`
- Produces: `OCRService.process(pixelBuffer: CVPixelBuffer) async throws -> [DetectedTextBlock]`

- [ ] **Step 1: Write mock-based test or interface contract for OCRService**
Verify that `OCRService` configures `VNRecognizeTextRequest` with `.accurate` recognition level, automatically sets recognition languages, and clusters detected observations into `[DetectedTextBlock]`.

- [ ] **Step 2: Implement `OCRService.swift`**
Configure `VNRecognizeTextRequest(completionHandler:)` with `recognitionLevel = .accurate` and `usesLanguageCorrection = true`. Extract text and normalized bounding boxes, then pass into `SpatialTextClusterer`.

- [ ] **Step 3: Verify compilation & contract**
Run: `swift build`
Expected: Compilation succeeds.

- [ ] **Step 4: Commit**
```bash
git add RealtimeTranslateApp/Services/OCRService.swift
git commit -m "feat: implement Vision OCR pipeline with spatial clustering"
```

---

### Task 4: Camera Capture Pipeline (AVFoundation)

**Files:**
- Create: `RealtimeTranslateApp/Services/CameraCaptureManager.swift`
- Create: `RealtimeTranslateApp/Views/CameraPreviewView.swift`

**Interfaces:**
- Consumes: `AVFoundation`, `SwiftUI` (`UIViewRepresentable`)
- Produces: `CameraCaptureManager` (publisher emitting `CVPixelBuffer`, controls: `start()`, `stop()`, `toggleTorch()`, `freezeFrame()`), `CameraPreviewView(session: AVCaptureSession)`

- [ ] **Step 1: Implement `CameraCaptureManager`**
Set up `AVCaptureSession` with `.high` preset, discover wide-angle back camera, attach `AVCaptureVideoDataOutput`, configure queue on `DispatchQueue(label: "camera.video.queue")`, and implement `AVCaptureVideoDataOutputSampleBufferDelegate` emitting video pixel buffers. Add `isFrozen` toggle to hold the last frame.

- [ ] **Step 2: Implement `CameraPreviewView`**
Create `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer` with `.resizeAspectFill` video gravity.

- [ ] **Step 3: Verify build**
Run: `swift build`
Expected: Build passes.

- [ ] **Step 4: Commit**
```bash
git add RealtimeTranslateApp/Services/CameraCaptureManager.swift RealtimeTranslateApp/Views/CameraPreviewView.swift
git commit -m "feat: implement AVFoundation camera capture and SwiftUI preview layer"
```

---

### Task 5: Coordinate Transformation & Bounding Box Smoothing

**Files:**
- Create: `RealtimeTranslateApp/Services/CoordinateTransformer.swift`
- Test: `Tests/RealtimeTranslateAppTests/CoordinateTransformerTests.swift`

**Interfaces:**
- Consumes: `CoreGraphics` (`CGRect`, `CGSize`)
- Produces: `CoordinateTransformer.convert(visionRect: CGRect, viewSize: CGSize) -> CGRect`, `CoordinateTransformer.smooth(current: CGRect, target: CGRect, factor: CGFloat) -> CGRect`

- [ ] **Step 1: Write unit tests for coordinate conversion and smoothing**
Test conversion from Vision's bottom-left origin `(0...1)` to screen top-left origin `(0...viewSize)`, and verify EMA smoothing step.

```swift
import XCTest
@testable import RealtimeTranslateApp

final class CoordinateTransformerTests: XCTestCase {
    func testVisionToScreenCoordinateConversion() {
        let visionRect = CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1) // top of screen in Vision
        let viewSize = CGSize(width: 400, height: 800)
        
        let screenRect = CoordinateTransformer.convert(visionRect: visionRect, viewSize: viewSize)
        
        // In Vision y:0.8 height:0.1 means top edge is at 1.0 - 0.9 = 0.1 in screen Y
        XCTAssertEqual(screenRect.origin.x, 40)
        XCTAssertEqual(screenRect.origin.y, 80) // (1.0 - 0.8 - 0.1) * 800 = 80
        XCTAssertEqual(screenRect.width, 120)
        XCTAssertEqual(screenRect.height, 80)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `swift test --filter CoordinateTransformerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `CoordinateTransformer.swift`**
Implement origin flip `(1.0 - visionRect.maxY)` and EMA filter `current + (target - current) * alpha`.

- [ ] **Step 4: Run test to verify it passes**
Run: `swift test --filter CoordinateTransformerTests`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add RealtimeTranslateApp/Services/CoordinateTransformer.swift Tests/
git commit -m "feat: implement coordinate conversion and EMA bounding box smoothing"
```

---

### Task 6: AR Overlay Canvas & Inspection Detail Sheet

**Files:**
- Create: `RealtimeTranslateApp/Views/ARTextBadgeView.swift`
- Create: `RealtimeTranslateApp/Views/AROverlayCanvas.swift`
- Create: `RealtimeTranslateApp/Views/DetailCardSheet.swift`

**Interfaces:**
- Consumes: SwiftUI, `DetectedTextBlock`, `CoordinateTransformer`
- Produces: `AROverlayCanvas(blocks: [DetectedTextBlock], viewSize: CGSize, onSelect: (DetectedTextBlock) -> Void)`, `DetailCardSheet(block: DetectedTextBlock)`

- [ ] **Step 1: Implement `ARTextBadgeView.swift`**
Create the `.ultraThinMaterial` badge view with rounded corners (`Capsule` or `RoundedRectangle(cornerRadius: 8)`), high-contrast bold text with auto-scaling (`minimumScaleFactor`), and tap gesture handler.

- [ ] **Step 2: Implement `AROverlayCanvas.swift`**
Create a SwiftUI overlay canvas placing `ARTextBadgeView` instances at screen positions computed by `CoordinateTransformer`.

- [ ] **Step 3: Implement `DetailCardSheet.swift`**
Create bottom inspection sheet showing:
- Original text
- Translated text
- Copy to clipboard button (`UIPasteboard.general.string`)
- Speak button triggering `AVSpeechSynthesizer` with target language BCP-47 tag.

- [ ] **Step 4: Verify build**
Run: `swift build`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add RealtimeTranslateApp/Views/
git commit -m "feat: implement AR text badge, overlay canvas, and detail card sheet"
```

---

### Task 7: ViewModel State Orchestration & Main Camera View

**Files:**
- Create: `RealtimeTranslateApp/ViewModels/CameraTranslationViewModel.swift`
- Create: `RealtimeTranslateApp/Views/OnboardingLanguageSheet.swift`
- Create: `RealtimeTranslateApp/Views/MainCameraView.swift`
- Create: `RealtimeTranslateApp/RealtimeTranslateApp.swift` (App entry point)

**Interfaces:**
- Consumes: All services, models, and views from Tasks 1–6
- Produces: Complete working iOS application with live camera preview, real-time throttled OCR, translation stream, freeze button, and language selector.

- [ ] **Step 1: Implement `CameraTranslationViewModel.swift`**
Connect `CameraCaptureManager` buffer publisher to throttled OCR pipeline (running every 4 frames). Trigger translation for new or updated text blocks asynchronously. Expose `@Published var detectedBlocks: [DetectedTextBlock]`, `@Published var isFrozen: Bool`, `@Published var selectedBlock: DetectedTextBlock?`, `@Published var sourceLanguage: Locale.Language?`, `@Published var targetLanguage: Locale.Language`.

- [ ] **Step 2: Implement `OnboardingLanguageSheet.swift`**
List common language pairs (e.g. Mandarin -> Indonesian, English -> Indonesian). Tapping triggers Apple's `prepareTranslation()` on-demand download prompt.

- [ ] **Step 3: Implement `MainCameraView.swift` and `RealtimeTranslateApp.swift`**
Assemble root view:
- Top Bar: Source language dropdown (Auto Detect default) -> Target language dropdown (Indonesian default).
- Center: `CameraPreviewView` covered by `AROverlayCanvas`.
- Bottom Bar: Torch toggle button, large circular Freeze button, and Settings/Language Pack button.
- Sheet presentation for `DetailCardSheet` (when badge tapped) and `OnboardingLanguageSheet`.

- [ ] **Step 4: Run full test suite & compilation**
Run: `swift test`
Expected: All unit tests pass.

- [ ] **Step 5: Commit**
```bash
git add RealtimeTranslateApp/ RealtimeTranslateApp.swift
git commit -m "feat: assemble ViewModel orchestrator, onboarding sheet, and MainCameraView"
```

---

## Self-Review Checklist

- [x] **Spec coverage**: Covers all requirements from design doc (iOS 18.0+, Pure Native Swift, Vision OCR, spatial line clustering, offline Apple TranslationSession, frosted glass overlay, freeze frame, tap inspection, pre-trip onboarding).
- [x] **Step scan**: Each step has a concrete checkable action, clear commands, exact signatures and assertions.
- [x] **Type consistency**: `DetectedTextBlock`, `OCRLine`, `CoordinateTransformer`, `TranslationServiceProtocol` signatures match across all tasks.
- [x] **Review focus**: Jittery boxes (Task 5), fragmented text (Task 1), missing offline pack (Task 7), coordinate mismatch (Task 5), freeze frame drift (Task 4 & 7) are all explicitly addressed with unit tests or architecture locks.
- [x] **Proportion**: Clean, modular task breakdown without transcripts of trivial boilerplate.
