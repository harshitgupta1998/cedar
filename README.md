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

Open a saved transcript → **Offline notes**, download Qwen3 0.6B and tap **Generate notes**. Version 0.7.0 produces a Summary, Action items, and Suggested follow-ups. This Apache 2.0 model is a 396,705,472-byte download (397 MB), pinned to a Hugging Face revision and verified by size and SHA-256 before installation and inference. Processing runs locally after download.

Version 0.6.0 replaces SmolLM2 360M and Qwen3 1.7B. Launching the app removes their two downloaded weight files (about 1.38 GB if both were installed). Saved recordings, transcripts, notes and revisions are retained. Old notes keep their original model attribution. Removing unused weights frees storage; memory savings during inference come from the new model and smaller context.

Long transcripts are split using the actual model tokenizer, with at most 900 prompt tokens and 600 output tokens per section in a fixed 1,536-token context. One model and context are reused sequentially, with the attention cache cleared between sections. Every source word is included once; oversized input produces an error instead of silent truncation. Longer text therefore increases processing time rather than context memory.

The target is about an hour of English speech. Limits are **16,000 words, 180,000 characters and 64 sections**, whichever is reached first. Duration is only a rough guide: speaking rate and tokenization vary. Section notes follow transcript order; later sections can revise earlier decisions. An overall summary appears first, with section recaps retained below. Long summaries select complete source statements by relevance, avoiding a free-form rewrite by the tiny model. The method is labeled in the output; this can still omit context or retain an earlier statement that is corrected later. These text limits do not cap recording duration. Actual hour-long capture and transcription remain unverified.

Downloads show progress and support cancellation/retry. Uncommitted staging is cleaned up on launch. Model files are excluded from iCloud backups and Git. Keep Cedar open during generation; the screen stays awake. Leaving the notes screen or backgrounding the app cancels the run, keeping previous saved notes. Cancelled/failed jobs do not save partial notes. The model and context are unloaded at the end of the run. Transcription also keeps the screen awake while active.

Action items include source excerpts and only source-supported owner/deadline fields. Conditional, negated and completed statements are filtered from committed next steps. Suggested follow-ups are questions about unresolved issues, clearly labeled as recommendations rather than commitments. Exact quotes are checked and expanded to their surrounding sentence where possible. Invalid generated items are omitted with a visible review note. A deterministic pass also retains explicit named commitments and short personal reminders the model may miss. These checks improve traceability; they do not prove semantic correctness.

Use **Edit notes**, **Copy notes**, **Share notes**, or **Previous versions** below saved notes. Regeneration and edits archive the previous text. Restoring a version archives the current one first. Outdated notes keep their original transcript identity and stay labeled outdated after editing. Concurrent edits are rejected.

Review notes against the transcript. Small models can omit facts or introduce unsupported conclusions, particularly in long or repetitive text. Short synthetic checks and hour-length text throughput checks are separate evidence; neither certifies real-conversation accuracy. See [raw results, known failures and reproduction steps](evaluation/README.md).

Model and runtime licenses are available in the app: [Qwen3 0.6B](https://huggingface.co/Qwen/Qwen3-0.6B), [pinned compressed weights](https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/tree/50968a4468ef4233ed78cd7c3de230dd1d61a56b), and [llama.cpp b9000](https://github.com/ggml-org/llama.cpp/tree/b9000). Historical model notices are retained in the repository.

Optional real-inference tests require the pinned weight file in the test host's `Library/Application Support/CedarModels/` directory. CI skips model-dependent cases when weights are absent. Tests cover splitting without dropped words, input/cancellation limits, retired-weight cleanup, inference, storage/recovery, edits/restoration, download progress and failures.

## Recovery

Cedar retains a previous valid recording manifest. Damaged or missing metadata is reconstructed from that backup or the recording folder, so retained audio stays visible even when metadata repair cannot be written. Damaged metadata is copied into a local `Recovery` folder before replacement. Unreadable audio stays marked for recovery. Use **Retry recovery** in its recording detail screen.

If saved transcript or notes JSON is damaged, Cedar tries the newest valid archived revision and shows a recovery notice. A restored revision can be older than the damaged document. Automatic recovery never resumes microphone capture. See [recording checks](docs/recording-checks.md).

## Current milestone

See [development status](docs/development-status.md). Cedar 0.7.0 is installed on the actual iPhone 13 (now iOS 27.2.1). Short recording/playback, offline transcription and 360M notes have been verified by the user. The user also confirmed that Qwen3 1.7B failed with insufficient app memory in the regular app. Qwen3 0.6B replaces it, and the user confirmed successful generation in the regular app. It also completed a 9,141-word synthetic transcript on this iPhone in 48.7 seconds without a memory error. This verifies text processing, not hour-long audio capture/transcription or factual accuracy. Longer recording and interruption checks remain open. See [recording checks and limits](docs/recording-checks.md).

## License

Cedar is [MIT](LICENSE). SmolLM2 and Qwen3 model weights are Apache 2.0 and the llama.cpp runtime is MIT. Bundled notices are in `ios/Cedar/Notices`.
