# Wiki's Lazy Coders Challenge - WebM Camera & Wikimedia Commons Uploader

A native Android application built with Flutter and Kotlin that records video directly into **genuine WebM format** (without recording MP4 and converting afterward) and provides an end-to-end workflow for uploading compliant video recordings to **Wikimedia Commons**.

---

## 1. Project Overview & Challenge Objective

Wikimedia Commons requires open video formats—primarily WebM (VP8/VP9 video codecs with Vorbis or Opus audio codecs). Most Android camera applications record MP4 (H.264/AAC) containers. Simply recording MP4 and converting it after the fact adds significant processing overhead, degrades video quality, consumes battery, and fails the core requirement of this challenge.

This application implements:
1. **Direct Native WebM Recording**:
   - Camera2 API pipeline coupled with Android's native `MediaRecorder` or `MediaCodec` configured explicitly for `OutputFormat.WEBM` with `VideoEncoder.VP8` / `VideoEncoder.VP9` and `AudioEncoder.OPUS` / `AudioEncoder.VORBIS`.
   - Native EBML header inspection (`0x1A45DFA3`) and `DocType: webm` byte-level verification to prove that recorded files are authentic WebM containers, not renamed MP4s.
   - Live hardware camera preview displayed via Flutter's `TextureRegistry` surface textures for edge-to-edge preview performance.
2. **Wikimedia Commons Integration**:
   - OAuth 2.0 authorization-code flow with PKCE (RFC 7636) for secure user authentication without storing passwords or embedding client secrets.
   - CSRF token acquisition (`meta=tokens&type=csrf`).
   - Action API upload pipeline (`action=upload`) with support for multipart uploads and chunked stashing for large recordings.
   - Comprehensive metadata collection (page title, description, recording date, voluntary GPS coordinates, author attribution, and free license confirmation such as CC BY-SA 4.0, CC BY 4.0, CC0 1.0).
   - Direct link to the uploaded Wikimedia Commons file page upon success.
3. **Local Gallery & Playback**:
   - Local recording manager with duration, file size, thumbnail generation, WebM container diagnostic verification, and built-in playback.

---

## 2. Architecture & Technology Stack

```
                     ┌───────────────────────────────────────────────┐
                     │                 Flutter UI                    │
                     │  - Camera Screen (Edge-to-edge preview)       │
                     │  - Recordings Gallery & Video Player          │
                     │  - Wikimedia OAuth & Connection Screen        │
                     │  - Metadata Collection & Upload Progress      │
                     │  - Resolution / Codec / Audio Settings        │
                     └───────────────────────┬───────────────────────┘
                                             │ MethodChannel & EventChannel
                     ┌───────────────────────▼───────────────────────┐
                     │          Android Platform Channel             │
                     │  org.wikimedia.wikilazycoders/camera          │
                     └───────────────────────┬───────────────────────┘
                                             │
               ┌─────────────────────────────┴─────────────────────────────┐
               ▼                                                           ▼
┌───────────────────────────────┐                       ┌───────────────────────────────┐
│     Kotlin Camera2 Service    │                       │     Native WebM Recorder      │
│  - CameraManager & Devices    │                       │  - MediaRecorder.WEBM (VP8)   │
│  - Flutter TextureRegistry    │                       │  - AudioEncoder (OPUS/VORBIS) │
│  - Surface & Target Capture   │                       │  - Byte-Level EBML Validator  │
└───────────────────────────────┘                       └───────────────────────────────┘
                                                                        │
                                                        ┌───────────────▼───────────────┐
                                                        │  Wikimedia Commons Action API │
                                                        │  - OAuth 2.0 PKCE Flow        │
                                                        │  - CSRF Token & Upload API    │
                                                        └───────────────────────────────┘
```

### Core Technologies
- **UI & State**: Flutter 3.47+ (Dart 3.13+)
- **Native Android**: Kotlin 2.1+, Android Camera2 API, Android MediaRecorder / MediaCodec
- **Platform Interop**: Flutter `MethodChannel` (`org.wikimedia.wikilazycoders/camera`), `EventChannel` for recording state, and `TextureRegistry` for zero-copy preview rendering
- **Networking & Commons API**: `dio` & `http` client for MediaWiki Action API (`https://commons.wikimedia.org/w/api.php`)
- **Authentication**: OAuth 2.0 Authorization Code with PKCE (`crypto` for SHA-256 code challenge generation)
- **Secure Storage**: `flutter_secure_storage` backed by Android Keystore
- **Video Playback**: `video_player` plugin

---

## 3. WebM Container & Codec Verification Standard

Every recorded file must satisfy Wikimedia Commons Video Guidelines:
1. **Container**: WebM (`video/webm`)
2. **Video Codec**: VP8 or VP9
3. **Audio Codec**: Opus (preferred) or Vorbis

### Byte-Level EBML Verification
A genuine WebM file starts with the EBML Header tag `[0x1A, 0x45, 0xDF, 0xA3]`. Inside the EBML header, the `DocType` element (ID `0x42, 0x82`) contains the ASCII string `"webm"`. In contrast:
- MP4 files begin with `ftyp` box signatures (e.g. `isom`, `mp42`).
- Renamed MP4 files have MP4 signatures regardless of the `.webm` extension.

The native Kotlin module includes an `EbmlValidator` that inspects the file header and parses the tracks via Android's `MediaExtractor` to verify MIME types (`video/x-vnd.on2.vp8`, `audio/opus`), rejecting any file that fails validation.

---

## 4. Android Permissions

The application requests and handles the following Android runtime permissions:
- `android.permission.CAMERA`: Live preview and video frame capture.
- `android.permission.RECORD_AUDIO`: Microphone audio capture for Vorbis/Opus encoding.
- `android.permission.ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`: Optional geolocation metadata for Commons uploads.
- `android.permission.INTERNET`: Communicating with Wikimedia OAuth and Commons Action API.
- `android.permission.ACCESS_NETWORK_STATE`: Detecting network reachability and upload retry scheduling.

---

## 5. Development & Build Setup

### Prerequisites
- Flutter SDK 3.47.7+
- Android SDK 35 (Build-tools 35.0.0+)
- Java JDK 17+ / 21+

### Build & Verification Commands
```bash
# Fetch dependencies
flutter pub get

# Run static analysis
flutter analyze

# Run unit tests
flutter test

# Build debug APK
flutter build apk --debug
```

---

## 6. Wikimedia OAuth 2.0 Configuration

To authenticate with Wikimedia Commons:
1. Register an OAuth 2.0 client on [Wikimedia Meta-Wiki / Commons](https://commons.wikimedia.org/wiki/Special:OAuthConsumerRegistration/propose).
2. Set Client Type to **Public (native/mobile application)**.
3. Set the Redirect URI to `wikilazycoders://oauth`.
4. In the app settings screen, enter your registered **Client ID** (or use the pre-configured default for testing).
5. The application will launch the browser for authorization using PKCE (`code_verifier` + `code_challenge` SHA-256) and handle the redirect callback securely into Android Keystore storage.

---

## 7. Automated Test Suite & Verification Results

The project maintains a test suite covering native models, authentication, and Wikimedia API integration:

| Test Suite | File | Tests | Status |
| :--- | :--- | :--- | :--- |
| **App Shell & Navigation** | [`test/widget_test.dart`](file:///c:/Users/vaibh/wiki/test/widget_test.dart) | 1 | Passed |
| **Wikimedia OAuth & PKCE** | [`test/auth_service_test.dart`](file:///c:/Users/vaibh/wiki/test/auth_service_test.dart) | 4 | Passed |
| **Commons Upload & Stash API** | [`test/upload_service_test.dart`](file:///c:/Users/vaibh/wiki/test/upload_service_test.dart) | 11 | Passed |
| **Camera & WebM Models** | [`test/camera_models_test.dart`](file:///c:/Users/vaibh/wiki/test/camera_models_test.dart) | 5 | Passed |
| **Total** | | **21 Tests** | **All Passed (0 failures)** |

Run tests locally:
```bash
flutter test
```

Static analysis verification:
```bash
flutter analyze
# Result: No issues found!
```

---

## 8. Milestone Implementation History

- **Milestone 1**: `chore: initialize Flutter Android project` - Scaffolding of project structure, dependencies, Android manifest permissions.
- **Milestone 2**: `docs: add project requirements and setup guide` - Architecture blueprint, WebM standards, API documentation.
- **Milestone 3**: `feat(android): implement WebM recording proof of concept` - Android Camera2 integration with `MediaRecorder` using `OutputFormat.WEBM`, `VideoEncoder.VP8`, `AudioEncoder.VORBIS`, and `TextureRegistry`.
- **Milestone 4**: `test(android): validate WebM container and codecs` - Low-level EBML header parsing (`0x1A45DFA3`, `DocType: webm`) and Track/Codec verification.
- **Milestone 5**: `feat(camera): add Flutter camera interface` - Camera screen, edge-to-edge preview, elapsed recording timer, resolution & camera switching.
- **Milestone 6**: `feat(recordings): add local gallery and playback` - Recording item list, file size formatting, video player with diagnostic card, sharing and deletion.
- **Milestone 7**: `feat(auth): implement Wikimedia OAuth` - OAuth 2.0 PKCE authorization flow, token refresh, and user profile management.
- **Milestone 8**: `feat(upload): integrate Wikimedia Commons API` - Direct multipart and chunked Stash API upload, CSRF token acquisition, duplicate detection.
- **Milestone 9**: `feat(ui): polish camera and upload workflows` - Hardware capabilities inspector, app preferences, bottom navigation shell.
- **Milestone 10**: `test: add application tests and fix defects` - 21 automated unit tests across all application layers.
- **Milestone 11**: `docs: document setup and verification results` - Comprehensive documentation and test matrix.
