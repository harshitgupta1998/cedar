# Development status

## Welcome-screen checkpoint

- [x] Native SwiftUI project targeting iPhone, iOS 17+.
- [x] Welcome screen, navigation to empty library, and app icon.
- [x] Shared Xcode scheme and UI smoke test.
- [x] Full simulator build and UI smoke test verified on iPhone 13 / iOS 26.5 (1 test, 0 failures).
- [x] Physical iPhone 13 signing, installation, and launch verified.

The welcome checkpoint is complete. Cedar 0.2.0 adds local recording, persistent audio and metadata, playback/seek, rename, and recoverable deletion. Transcription and cloud processing are not implemented. No private reference documents are included in the public repository.

## Local recording checkpoint

- [x] Capture → local save → library → playback.
- [x] Rename, Recently Deleted, and restore.
- [x] Storage/recovery unit tests.
- [x] Short real iPhone locked-screen recording and complete playback confirmed by the user.
- [x] Full simulator recording UI test, including persistence, playback/seek, rename, and delete/restore.
- [ ] Full 30-minute, offline, and interruption device matrix.

See [recording checks](recording-checks.md). Complete the longer reliability checks before treating this as durable daily recording, then evaluate speech support and transcription.

## Verification evidence — November 8, 2026

- Xcode 26.5; deployment target iOS 17.0.
- Full simulator build, including app icon, passed.
- UI smoke test passed on iPhone 13 / iOS 26.5: welcome → library → back (1 test, 0 failures).
- Welcome layout visually reviewed at iPhone 13 size.
- Actual iPhone 13 detected with iOS 26.5.2, paired, Developer Mode enabled.
- Signed device build, installation, and launch succeeded on the actual iPhone 13 after the user trusted the development profile. The running Cedar process was confirmed on the device.
- Signing settings are in ignored `ios/Local.xcconfig`; credentials and private reference documents are excluded from the repository.
- Five storage tests passed; both welcome navigation and the full recording UI flow have passing simulator runs.
- GitHub Actions builds the simulator app and runs storage/recovery tests on pushes to main and pull requests.

## Reliability follow-up — November 9, 2026

Cedar 0.2.1 improves the Record-control layout for large text and landscape. Added simulator force-quit recovery and microphone-denial checks, real-audio tests of interruption notification handlers, and a metadata-write failure test. Six storage, three audio-controller, and all five UI tests passed. Largest-text portrait and landscape screenshots were reviewed, and the signed 0.2.1 device build passed.

Offline capture/playback was user-confirmed; the displayed duration is still needed to verify the extended locked-screen test. A real phone interruption, low-storage device testing, and VoiceOver review remain open. Transcription has not started.
