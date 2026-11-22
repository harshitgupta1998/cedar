# Cedar

A native, local-first iPhone app for thoughts and conversations. Record conversations on your iPhone, save and play them offline, rename them, and restore items from Recently Deleted. Create timestamped on-device transcripts, edit their text, and generate experimental offline summaries, edit them, copy/share them, and restore earlier versions. Cloud features are future milestones.

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

Open a saved transcript → **Offline notes**, choose a model, download it and tap **Generate notes**. Downloads come from pinned Hugging Face revisions and are verified by file size and SHA-256 before installation and inference. Processing runs locally after download. Both models are Apache 2.0 licensed.

| Model | Download | Input budget including instructions | Context |
| --- | --- | --- | --- |
| SmolLM2 360M Q4_K_M | 271 MB | 3,500 tokens | 4,096 tokens |
| Qwen3 1.7B Q4_K_M | 1.11 GB | 1,600 tokens | 2,048 tokens |

Qwen3 uses its published non-thinking template. Start with short English recordings around five minutes or less. Both models allow up to 384 output tokens. Longer input produces a clear error. These text budgets do not cap recording duration. The larger model trades more memory and storage for better results in the tested examples. The app checks its available memory before loading a model. A larger model may be unavailable on a device or under current memory pressure.

Downloads show progress and can be cancelled and retried. Uncommitted staging files from a terminated download are cleaned up on launch. Model files are excluded from iCloud backups and Git. The selected model can be removed from the notes screen. Keep Cedar open during generation. Leaving the screen or backgrounding the app cancels generation. The model and context are unloaded after each request.

Use **Edit notes**, **Copy notes**, **Share notes**, or **Previous versions** below the saved summary. Regeneration and edits archive the previous text. Restoring a version archives the current one first. Outdated notes retain their original transcript identity and remain labeled outdated after editing. Concurrent edits are rejected instead of overwriting newer text.

Review summaries against the transcript. Small models can omit details or invent facts. The summary evaluation improved from 4/7 baseline checks to 6/7 with the revised 360M prompt; Qwen3 passed 7/7 main and 4/4 additional synthetic checks. These limited Mac results do not establish general accuracy. Outputs, limitations and reproduction steps are in [the local evaluation](evaluation/README.md).

Model and runtime licenses are available in the app. Sources include [SmolLM2](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct), [Qwen3](https://huggingface.co/Qwen/Qwen3-1.7B), [the Qwen3 conversion](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF), and [llama.cpp b9000](https://github.com/ggml-org/llama.cpp/tree/b9000).

Optional real-inference tests run when the pinned model files are installed in the test host's `Library/Application Support/CedarModels/` directory. CI skips these two cases when the model files are absent. Local tests cover both real models, storage and recovery, editing, restoration, download progress, HTTP failure and cancellation.

## Recovery

Cedar retains a previous valid recording manifest. Damaged or missing metadata is reconstructed from that backup or the recording folder, so retained audio stays visible even when metadata repair cannot be written. Damaged metadata is copied into a local `Recovery` folder before replacement. Unreadable audio stays marked for recovery. Use **Retry recovery** in its recording detail screen.

If saved transcript or notes JSON is damaged, Cedar tries the newest valid archived revision and shows a recovery notice. A restored revision can be older than the damaged document. Automatic recovery never resumes microphone capture. See [recording checks](docs/recording-checks.md).

## Current milestone

See [development status](docs/development-status.md). Cedar 0.5.0 is installed on the actual iPhone 13 (now iOS 27.2.1). Short recording/playback, offline transcription and 360M notes have been verified by the user. The optional Qwen3 1.7B model passed simulator inference but was rejected by the physical-device test runner’s memory preflight; regular-app verification is pending. Longer recording and interruption checks remain open. See [recording checks and limits](docs/recording-checks.md).

## License

Cedar is [MIT](LICENSE). SmolLM2 and Qwen3 model weights are Apache 2.0 and the llama.cpp runtime is MIT. Bundled notices are in `ios/Cedar/Notices`.
