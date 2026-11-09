# Development status

## Welcome-screen checkpoint

- [x] Native SwiftUI project targeting iPhone, iOS 17+.
- [x] Welcome screen, navigation to empty library, and app icon.
- [x] Shared Xcode scheme and UI smoke test.
- [x] Full simulator build and UI smoke test verified on iPhone 13 / iOS 26.5 (1 test, 0 failures).
- [x] Physical iPhone 13 signing, installation, and launch verified.

No recording, transcription, persistent storage, or cloud processing is implemented in this checkpoint. No private reference documents are included in the public repository.

## Next checkpoint

After the physical device launches this welcome screen, confirm its iOS version and speech capabilities. Then implement durable local recording, library, and playback before transcription and cloud features. Each stage requires its own device verification.

## Verification evidence — November 8, 2026

- Xcode 26.5; deployment target iOS 17.0.
- Full simulator build, including app icon, passed.
- UI smoke test passed on iPhone 13 / iOS 26.5: welcome → library → back (1 test, 0 failures).
- Welcome layout visually reviewed at iPhone 13 size.
- Actual iPhone 13 detected with iOS 26.5.2, paired, Developer Mode enabled.
- Signed device build, installation, and launch succeeded on the actual iPhone 13 after the user trusted the development profile. The running Cedar process was confirmed on the device.
- Signing settings are in ignored `ios/Local.xcconfig`; credentials and private reference documents are excluded from the repository.
- GitHub Actions builds the simulator app on pushes to main and pull requests.
