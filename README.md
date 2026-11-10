# Cedar

A native, local-first iPhone app for thoughts and conversations. Record conversations on your iPhone, save and play them offline, rename them, and restore items from Recently Deleted. Transcription and cloud features are future milestones.

## Run locally

Requirements: a Mac with Xcode 16 or later, an iOS Simulator runtime, or an iPhone running iOS 17 or later. Development verified with Xcode 26.5 and the iOS 26.5 Simulator runtime.

1. Open `ios/Cedar.xcodeproj` in Xcode.
2. Select the **Cedar** scheme and an iPhone simulator.
3. Press **Run** (Command-R).

No backend, API keys, paid services, or package installations are required. The app makes no network requests. Microphone permission is requested only when you tap Record.

## Install on your iPhone 13

1. Connect and unlock the iPhone. Accept **Trust This Computer** if prompted.
2. In Xcode > Settings > Apple Accounts, add your Apple Account.
3. Select the Cedar project, then the Cedar target > Signing & Capabilities. Keep **Automatically manage signing** enabled and select your team. A personal Apple Account can be used for local device testing; Xcode may require periodic re-signing.
4. The default bundle identifier is `com.harshitgupta1998.cedar`. If Xcode reports it unavailable, replace it with a unique identifier.
5. Enable **Settings > Privacy & Security > Developer Mode** on the iPhone and complete any requested restart/confirmation.
6. Select your physical iPhone as the Xcode run destination and press Command-R. Follow any signing or trust prompts displayed by Xcode and iOS.

For a team configuration that stays out of Git, create `ios/Local.xcconfig` with `DEVELOPMENT_TEAM = YOUR_TEAM_ID`. Both app and UI-test targets load this optional file through `ios/Config.xcconfig`. Selecting a team directly in Xcode may instead modify the project file.

Signing credentials and local team overrides stay on your Mac. Do not commit certificates or provisioning profiles. To use a team from the command line, pass `DEVELOPMENT_TEAM=YOUR_TEAM_ID` to `xcodebuild`.

Apple guides: [Run on devices](https://developer.apple.com/documentation/xcode/building-and-running-an-app), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Verify

```sh
xcodebuild -project ios/Cedar.xcodeproj -scheme Cedar \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

For the storage/recovery tests and UI recording flow, choose an available iPhone simulator in Xcode and press Command-U, or run:

```sh
xcodebuild -project ios/Cedar.xcodeproj -scheme Cedar \
  -destination 'platform=iOS Simulator,name=Cedar iPhone 13' \
  CODE_SIGNING_ALLOWED=NO test
```

The example test command requires an iPhone 13 simulator named **Cedar iPhone 13** to be created in Xcode's Device Hub. Another available iPhone simulator name works too. Select a working audio input in Simulator → I/O → Audio Input for microphone tests. Run only the storage tests with `-only-testing:CedarTests -skip-testing:CedarTests/AudioControllerTests` when no audio input is available. Audio-controller integration tests require microphone permission already granted in the simulator. UI tests use isolated simulator storage and skip physical devices.

## Current milestone

See [development status](docs/development-status.md). The welcome and short local-recording checkpoints are verified on the actual iPhone 13 (iOS 26.5.2), including a short locked-screen recording and audible playback. Longer recording and interruption checks remain open. See [recording checks and limits](docs/recording-checks.md).

## License

[MIT](LICENSE).
