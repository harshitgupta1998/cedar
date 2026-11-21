# Cedar

A native, local-first iPhone app for thoughts and conversations. Record conversations on your iPhone, save and play them offline, rename them, and restore items from Recently Deleted. Create timestamped on-device transcripts, edit their text, and try experimental offline summaries with SmolLM2 360M. Cloud features are future milestones.

## Run locally

Requirements: a Mac with Xcode 26 or later for SpeechAnalyzer (Xcode 16 builds use the bounded legacy speech fallback), an iOS Simulator runtime, or an iPhone running iOS 17 or later. Development verified with Xcode 26.5 and the iOS 26.5 Simulator runtime.

1. Run `python3 scripts/setup-inference.py` from the repository root. This downloads and verifies the pinned llama.cpp XCFramework.
2. Open `ios/Cedar.xcodeproj` in Xcode.
3. Select the **Cedar** scheme and an iPhone simulator.
4. Press **Run** (Command-R).

No backend, API keys, or paid services are required. The inference runtime is downloaded during developer setup. Audio and transcripts are processed and stored on the iPhone. Microphone permission is requested only when you tap Record; Speech Recognition permission is requested when you tap Transcribe. An optional Apple language-model download requires internet, but audio is not uploaded.

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

## Transcribe a recording

Open a recording → **Transcript**, choose a language, and tap **Transcribe recording**. If offered, use **Download language** first. Tap **Edit transcript** to correct text; timestamps keep pointing to the original audio. See [transcription verification and limits](docs/transcription-checks.md).

## Try offline notes

Open a saved transcript → **Offline notes** → **Download model · 271 MB** → **Generate notes**. The download comes from Hugging Face and is verified against a pinned SHA-256 hash. After download, inference runs locally through llama.cpp and works offline. The model can be removed from this screen. Its download is excluded from iCloud backups.

This experiment uses **SmolLM2-360M-Instruct Q4_K_M**. Start with short English recordings around five minutes or less. The full prompt must fit within 3,500 tokens, with a 4,096-token context and up to 384 generated tokens. Longer input is rejected with a message. Duration is guidance rather than an enforced recording limit. Keep Cedar open during generation. Leaving the screen or backgrounding the app cancels generation. The model is unloaded after each request.

Generated notes are saved alongside the recording and survive relaunch and Recently Deleted/restore. Regeneration archives the previous notes. Editing a transcript marks its existing notes as outdated. Cancellation and failed generation preserve saved notes. Review the summary against the transcript, especially decisions, names, dates and tasks. The model is experimental and may omit or invent details.

The model weights are downloaded separately and excluded from Git. Model and runtime licenses are available in the app. Source: [Hugging Face SmolLM2](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct), [Unsloth conversion](https://huggingface.co/unsloth/SmolLM2-360M-Instruct-GGUF), [llama.cpp b9000](https://github.com/ggml-org/llama.cpp/tree/b9000).

The optional real-inference integration test runs when the pinned model is installed in the test host app's `Library/Application Support/CedarModels/SmolLM2-360M-Q4_K_M.gguf`. It uses synthetic transcripts. CI skips that case when the model is absent and runs the remaining storage, integrity and speech-controller tests.

## Current milestone

See [development status](docs/development-status.md). The welcome and short local-recording checkpoints are verified on the actual iPhone 13 (iOS 26.5.2), including short audio capture and audible playback. Longer recording and interruption checks remain open. See [recording checks and limits](docs/recording-checks.md).

## License

Cedar is [MIT](LICENSE). SmolLM2 model weights are Apache 2.0 and the llama.cpp runtime is MIT. Bundled notices are in `ios/Cedar/Notices`.
