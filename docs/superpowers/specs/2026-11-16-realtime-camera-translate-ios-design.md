# Design Document: Real-Time Camera Translation iOS App (Offline-First)

* **Date:** 2026-11-16
* **Status:** Ready for Approval
* **Target Platform:** iOS 18.0+ (iPhone)
* **Author / Architecture:** Pure Native Swift & SwiftUI

---

## 1. Intent & Context (The Why)

When travelers, expats, or language learners encounter foreign text in physical environments (such as restaurant menus, street signs, transit maps, and store labels in Chinese Mandarin or other languages), they often struggle to understand or type it out manually. 

Existing solutions either require constant internet connectivity (which is expensive or inaccessible while traveling abroad without roaming) or introduce sluggish frame rates and disruptive ads. 

This project aims to deliver a lightning-fast, privacy-first, **100% offline real-time camera translation** experience on iPhone, where pointing the camera at foreign text instantly renders crisp, readable translations directly over the scene.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- **Real-Time Camera OCR**: High-throughput text detection and recognition on live camera frames via Apple's Vision framework and Neural Engine.
- **Offline-First Translation**: Perform translation entirely on-device without internet access via Apple's native `TranslationSession` API.
- **Auto-Language Detection & Target Selection**: Automatically identify the source script (e.g., Mandarin) and translate to the chosen destination language (e.g., Indonesian).
- **Spatial Block Clustering**: Intelligently group nearby text lines (especially for logographic scripts like Chinese) into coherent semantic blocks before translation to preserve contextual meaning.
- **Ergonomic AR UI**: Display translated text cleanly over original text using frosted-glass badges (`.ultraThinMaterial`) that remain legible regardless of background visual clutter.
- **Freeze Frame Capability**: Allow the user to pause/freeze the live camera feed at any moment to read translations comfortably without holding their arm steady.
- **Interactive Inspection**: Allow tapping on any translated badge to view details (original text, translation, pronunciation/pinyin if applicable, and copy to clipboard).
- **Pre-Trip Language Onboarding**: Guide users to pre-download their desired language packs while connected so offline mode is guaranteed when traveling.

### Non-Goals
- **Live Voice / Audio Speech Translation**: Focused exclusively on printed and digital visual text in camera feed (OCR to text translation).
- **Full Handwriting Deciphering**: While Vision handles neat handwriting, the primary goal is printed text (signage, menus, packaging, books).
- **Cloud Account / Social Features**: No login, user tracking, or backend database needed.

### Anti-Goals
- **Cluttered AR Gimmicks**: Avoid invasive 3D AR or unstable in-place text replacement that flickers or causes motion sickness.
- **Mandatory Cloud / Data Consumption**: The app must never fail or block the user just because there is no internet connection once the language pack is downloaded.

---

## 3. Constraints & Technical Calls

- **Minimum iOS Version (Architect's Call)**: **iOS 18.0+**. Apple's programmatic on-device `TranslationSession` and batch translation API (`prepareTranslation()`, `batchTranslation`) were officially launched in iOS 18.0. Setting iOS 18.0+ as the deployment target allows pure native execution with zero third-party SDK bloat.
- **Hardware Requirement**: iPhone with Apple A12 Bionic or newer (Neural Engine accelerated).
- **Permissions**: Requires Camera Access permission (`NSCameraUsageDescription`).
- **Language Pack Delivery (Architect's Call)**: Apple on-device models are managed by the iOS operating system (~30MB–50MB per language). The app features an intuitive onboarding checklist ("Persiapan Bepergian / Pre-Trip Download") that triggers Apple's native `prepareTranslation()` download sheet while connected.
- **OCR Granularity (Architect's Call)**: Spatial 2D line clustering. Nearby lines are merged into semantic paragraphs before passing to the translator, preventing fragmented Mandarin character translation.
- **Auto-Detect Handling (Architect's Call)**: Uses Apple's on-device `NaturalLanguage` framework (`NLLanguageRecognizer`) to evaluate the dominant script in the camera view silently, avoiding disruptive modal system prompts during live camera feeds.

---

## 4. Approaches Considered

1. **Approach 1: Pure Native iOS (SwiftUI + AVFoundation + Vision + Translation Framework) — *SELECTED***
   - *How it works*: Native AVFoundation capture pipeline feeds frames to `VNRecognizeTextRequest`. Clustered text blocks are fed into `TranslationSession`. SwiftUI canvas overlays frosted-glass badges mapped to normalized bounding boxes.
   - *Pros*: Zero third-party dependencies, minimal app size (~10MB), 60 FPS camera feed, optimized for Apple Neural Engine, zero API costs, completely offline.
   - *Cons*: Limited to ~20+ major languages officially supported by Apple on-device models.
   - *Decision*: Chosen by user for maximum responsiveness, battery efficiency, and clean native iOS experience.

2. **Approach 2: Native iOS + Google ML Kit Translate**
   - *How it works*: Swift/SwiftUI with Google ML Kit Translate SDK for translation.
   - *Pros*: Supports 59+ offline languages.
   - *Cons*: Increases app binary size by 30-40MB, requires CocoaPods/SPM integration, higher complexity for language model asset downloads.
   - *Decision*: Kept as a future extension if languages outside Apple's support are requested.

3. **Approach 3: Cross-Platform (Flutter / React Native)**
   - *How it works*: Hybrid framework wrapping native camera buffers.
   - *Pros*: Potential code reuse for Android.
   - *Cons*: Frame-buffer bridge overhead, lower FPS, jittery AR tracking, suboptimal developer experience for cutting-edge iOS Translation APIs.
   - *Decision*: Rejected due to latency and tracking stability concerns.

---

## 5. System Architecture & Components

```
+-------------------------------------------------------------------------+
|                              iOS CAMERA FEED                            |
|                 AVCaptureVideoDataOutput (60 FPS Stream)                |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                         VISION OCR PIPELINE                             |
|          VNRecognizeTextRequest (Apple Vision Framework)                |
|  - Throttled inference (every 3-5 frames for thermal & battery control)  |
|  - Spatial Line Clustering (merge neighboring lines into blocks)        |
|  - Output: Clustered Text + Normalized Bounding Boxes (CGRect)          |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                    ON-DEVICE TRANSLATION ENGINE                         |
|             Apple Translation Framework (iOS 18.0+)                     |
|  - Dominant script detected via NaturalLanguage (NLLanguageRecognizer)  |
|  - Batch translate text blocks asynchronously via TranslationSession    |
|  - Source: Auto-detect / Manual selection                               |
|  - Target: User Target Language (e.g. Indonesian)                       |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                        SWIFTUI AR OVERLAY VIEW                          |
|  - Coordinate conversion (Vision normalized Y-up to SwiftUI Y-down)     |
|  - Exponential Moving Average (EMA) bounding box smoothing              |
|  - Frosted Glass Badges (`.ultraThinMaterial`) over detected regions    |
|  - Top Bar: Language Selectors                                          |
|  - Bottom Bar: Freeze Frame Button + Flashlight Toggle                  |
|  - Detail Sheet: Tap on badge to open inspection card                   |
+-------------------------------------------------------------------------+
```

---

## 6. Detailed UX & UI Flow

### A. Main Camera Screen
- **Full-Screen Viewfinder**: Immersive edge-to-edge camera feed.
- **Top Control Bar**:
  - `Source Language`: Dropdown with "[Deteksi Otomatis]" as default, or manual selection (e.g. Mandarin).
  - Arrow icon `->`.
  - `Target Language`: Dropdown defaulting to system language (e.g. Bahasa Indonesia).
- **Overlay Elements**:
  - Each recognized text block is surrounded by a translucent pill/box with rounded corners.
  - Background: Adaptive translucent dark/light frosted blur (`.ultraThinMaterial`).
  - Text: High-contrast bold typography with dynamic type sizing matching original text box dimensions.
- **Bottom Control Bar**:
  - Left: Flashlight / Torch toggle button.
  - Center: **Freeze / Pause** button (large circular shutter icon with pause symbol).
  - Right: Language Pack Manager / Settings button.

### B. Freeze Mode
- Tapping the Freeze button pauses camera frame updates.
- The user can inspect the static image with all translated overlays pinned in place.
- Enables zooming (pinch-to-zoom) and panning on the captured frame.
- Tapping the button again resumes real-time camera tracking.

### C. Tap-to-Inspect Card
- When tapping any translated badge:
  - Highlights the selected badge with a primary accent border.
  - Presents a compact bottom card displaying:
    - Original text (with Pinyin / romanization for Asian languages).
    - Translated text in full.
    - Copy text button.
    - Pronounce / Text-to-Speech button (using `AVSpeechSynthesizer`).

### D. Language Pack Management & Onboarding
- First launch prompts the user: *"Unduh Paket Bahasa Sebelum Bepergian"* with one-tap download triggers for common pairs (e.g., Mandarin <-> Indonesia, English <-> Indonesia).
- Settings sheet lists available language pairs and their offline installation status.

---

## 7. What is Left to the Builder (Implementation Details)

- **Coordinate Mapping & Bounding Box Smoothing**: Converting normalized coordinate space `(0...1)` from Vision's bottom-left origin to UIKit/SwiftUI top-left origin, with an exponential moving average (EMA) filter to prevent AR badge flickering between consecutive video frames.
- **Frame Rate Optimization Strategy**: Running OCR on background threads (`DispatchQueue.global(qos: .userInitiated)`) at 5-10 Hz rather than 60 Hz to conserve battery and CPU temperature while maintaining smooth UI rendering.
- **State Persistence**: Persisting user language preferences in `@AppStorage` / `UserDefaults`.
