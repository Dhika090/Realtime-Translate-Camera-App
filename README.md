# Real-Time Camera Translation iOS App (Offline-First)

Aplikasi penerjemah kamera *real-time* berbasis **100% Offline-First** untuk iOS (iPhone) menggunakan teknologi bawaan Apple murni (**SwiftUI**, **AVFoundation**, **Vision**, **NaturalLanguage**, dan **Translation Framework**).

---

## 🌟 Fitur Utama

- **Real-Time Camera OCR**: Membaca teks asing (misal: Mandarin / Hanzi) secara *live* pada 60 FPS menggunakan Apple Neural Engine.
- **Pengelompokan Teks Spasial Cerdas (Spatial Clustering)**: Menggabungkan baris teks yang berdekatan menjadi satu kesatuan kalimat/menu tanpa jeda spasi aneh pada aksara Mandarin.
- **100% Terjemahan Offline**: Menggunakan `TranslationSession` (iOS 18+) tanpa kuota internet atau biaya server.
- **Deteksi Bahasa Otomatis**: Mendeteksi bahasa sumber secara senyap via `NaturalLanguage` (`NLLanguageRecognizer`).
- **Penghalus Kotak AR (EMA Smoothing)**: Teks terjemahan melayang di atas teks fisik (*frosted-glass badge* `.ultraThinMaterial`) tanpa getaran mikro (*anti-jitter*).
- **Fitur Freeze Frame**: Membekukan kamera untuk membaca teks menu/papan nama dengan santai.
- **Kartu Detail Inspeksi**: Mengetuk badge menampilkan teks asli, ejaan fonetik **Pinyin** (dengan tanda nada), tombol **Salin**, dan pengucapan suara **Text-to-Speech** (`AVSpeechSynthesizer`).
- **Panduan Pra-Perjalanan (Pre-Trip Onboarding)**: Memandu pengguna mengunduh model bahasa offline sebelum bepergian ke luar negeri.

---

## 📋 Kebutuhan Sistem

- **Mac** dengan macOS Sonoma (14.5+) atau macOS Sequoia (15.0+).
- **Xcode 16.0+**.
- **Perangkat**: iPhone fisik dengan **iOS 18.0+** (Chip A12 Bionic atau lebih baru).
  > *Catatan:* Untuk mencoba kamera langsung dianjurkan menggunakan iPhone fisik, karena Simulator Mac tidak memiliki kamera belakang fisik.

---

## 🚀 Cara Menjalankan Aplikasi di Xcode

### Langkah 1: Clone Repositori ke Mac Anda
Buka aplikasi **Terminal** di Mac Anda, lalu jalankan:
```bash
git clone https://github.com/Dhika090/Realtime-Translate-Camera-App.git
cd Realtime-Translate-Camera-App
```

---

### Langkah 2: Menjalankan di Xcode (Metode Rekomendasi)

1. Buka aplikasi **Xcode** di Mac Anda.
2. Pilih **Create New Project** -> Pilih tab **iOS** -> Pilih template **App** -> Klik **Next**.
3. Beri nama:
   - **Product Name:** `RealtimeTranslateApp`
   - **Interface:** `SwiftUI`
   - **Language:** `Swift`
   - **Minimum Deployment Target:** `iOS 18.0`
4. Setelah project terbuka, **hapus** file bawaan `ContentView.swift` dan `RealtimeTranslateAppApp.swift` yang dibuat otomatis oleh Xcode.
5. Seret (*Drag and Drop*) folder:
   - `RealtimeTranslateApp/`
   ke dalam navigator Xcode di sebelah kiri. Centang opsi **"Copy items if needed"** dan pilih target aplikasi Anda.
6. **Izin Kamera (PENTING):**
   - Buka target project -> Tab **Info**.
   - Tambahkan key: `Privacy - Camera Usage Description` (`NSCameraUsageDescription`).
   - Beri nilai penjelasan: *"Aplikasi ini membutuhkan akses kamera untuk menerjemahkan teks secara real-time."*
   *(Atau salin file `Info.plist` yang sudah kami sediakan).*

---

### Langkah 3: Sambungkan iPhone & Jalankan (Build & Run)

1. Sambungkan iPhone Anda ke Mac menggunakan kabel data (USB-C atau Lightning).
2. Di iPhone Anda, jika muncul pop-up *"Trust This Computer?"*, pilih **Trust**.
3. Di Xcode (bagian atas tengah jendela), pilih perangkat iPhone Anda sebagai target tujuan (bukan *Any iOS Device*).
4. Di tab **Signing & Capabilities**, pilih tim Apple ID gratis Anda (**Personal Team**) pada kolom *Team*.
5. Tekan tombol **Play / Run (`Cmd + R`)**.
6. Aplikasi akan terinstal di iPhone Anda!
   > *Catatan pertama kali instal:* Jika muncul pesan *Untrusted Developer* di iPhone, buka **Settings -> General -> VPN & Device Management** di iPhone Anda, lalu pilih Apple ID Anda dan klik **Trust**.
7. Buka aplikasi di iPhone, klik **Izinkan** saat meminta akses kamera, dan arahkan kamera ke teks berbahasa Mandarin atau asing lainnya!

---

## 🧪 Menjalankan Unit Test

Untuk menjalankan seluruh rangkaian pengujian unit (100+ skenario):
```bash
swift test
```
Atau di Xcode tekan shortcut **`Cmd + U`**.
