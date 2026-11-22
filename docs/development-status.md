# Development status

## Welcome-screen checkpoint

- [x] Native SwiftUI project targeting iPhone, iOS 17+.
- [x] Welcome screen, navigation to empty library, and app icon.
- [x] Shared Xcode scheme and UI smoke test.
- [x] Full simulator build and UI smoke test verified on iPhone 13 / iOS 26.5 (1 test, 0 failures).
- [x] Physical iPhone 13 signing, installation, and launch verified.

The welcome checkpoint is complete. Cedar 0.2.0 adds local recording, persistent audio and metadata, playback/seek, rename, and recoverable deletion. Cedar 0.3.0 adds on-device transcription, timestamp playback links, editable text, and retained local revisions. Cloud processing is not implemented. No private reference documents are included in the public repository.

## Local recording checkpoint

- [x] Capture → local save → library → playback.
- [x] Rename, Recently Deleted, and restore.
- [x] Storage/recovery unit tests.
- [x] Short real iPhone capture and audible playback confirmed by the user.
- [x] Full simulator recording UI test, including persistence, playback/seek, rename, and delete/restore.
- [ ] Full 30-minute, offline, and interruption device matrix.

See [recording checks](recording-checks.md). Complete the longer reliability checks before treating this as durable daily recording. Short-clip on-device transcription is verified below.

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

The user confirmed that the offline clip was deliberately short (9.68 seconds), and that a real Siri interruption stopped recording while retaining playable earlier audio. Version 0.2.1 (build 3) was installed on the iPhone 13 and verified through the device application inventory. The 30-minute locked-screen test, separate call/alarm cases, low-storage device testing, and VoiceOver review remain open. On-device transcription is now implemented; see the 0.3.0 checkpoint below.

## On-device transcription — 0.3.0

- [x] Runtime local-engine and language/model checks.
- [x] Explicit model download and speech permission at first transcription use.
- [x] Saved-recording transcription, timestamps, playback links, retry/cancel and local revisions.
- [x] Editable text persists across relaunch; audio remains separate.
- [x] iPhone 13 selects SpeechAnalyzer with English (United States) ready.
- [x] User confirmed short recognition, offline recognition and persistent manual edits.
- [x] Fifteen hardware-independent storage/controller tests passed.
- [x] Six UI regression cases have passing runs, including transcript capability checks and retained playback.
- [x] Final GitHub simulator build and fifteen hardware-independent tests passed ([run 42748918590](https://github.com/harshitgupta1998/cedar/actions/runs/42748918590)).
- [x] Version 0.3.0 (build 4) installed and verified on the iPhone 13.
- [ ] Actual-device long-recording transcription and broader speech evaluation.

See [transcription checks](transcription-checks.md). The user-deferred sustained-capture test remains open and does not block this work. Next, validate longer transcription and consent-controlled AI processing; there is no cloud backend in this build.

## Offline notes experiment — 0.4.0, November 21, 2026

SmolLM2 360M Instruct Q4_K_M is integrated through pinned llama.cpp b9000. The 270,590,560-byte model is downloaded explicitly from a pinned Unsloth revision on Hugging Face and verified by SHA-256 before installation and inference. Model weights and runtime binaries are excluded from Git. The developer setup script downloads and verifies the runtime. The app includes Apache 2.0 and MIT notices.

Open a saved transcript → Offline notes. The model generates a short English summary that is stored locally with the source transcript fingerprint, revision, model ID and elapsed processing time. Previous notes are archived on regeneration. Stale notes are labeled after transcript edits. Cancelled or failed work preserves saved notes. The engine unloads its model and context after each request.

Initial limits are 3,500 input tokens including instructions, a 4,096-token context and at most 384 output tokens. Around five minutes of speech is starting guidance. Longer input produces a clear error. Keeping the app open is required for this experiment. Long-conversation quality, battery use, thermal behavior and peak device memory remain to be measured.

The initial bullet-point prompt invented tasks in a synthetic test. The revised summary prompt preserved the tested rejected proposal and assigned dates, but this is a limited evaluation. The feature is explicitly experimental and summaries should be reviewed.

Simulator checks verified model download, cancellation/retry, actual generation, saved output, and cancellation of regeneration while retaining previous notes. All 19 hardware-independent tests passed locally, including real-model inference on short and longer synthetic text plus oversized-input rejection. The four new notes tests were rerun after the prompt revision. Two UI regression tests passed for welcome navigation and transcript capability checks with retained audio. [GitHub Actions run 44958665011](https://github.com/harshitgupta1998/cedar/actions/runs/44958665011) passed its simulator build and tests, with 18 tests passing and the optional real-model case skipped because CI does not download the model.

The iPhone 13 now reports iOS 27.2.1. The first 0.4.0 package installed and the verified model was copied to its app container. The user subsequently confirmed that Cedar generated offline notes successfully on the iPhone. Automated device inference remains unverified because of the XCTest signing failure.

## App icon — 0.4.1, November 21, 2026

Added a forest-green icon with a cream leaf and sound-wave detail, generated with ImageGen. The new CedarIcon asset is opaque and 1024 × 1024. Both app configurations select it, and the compiled app's primary icon metadata references CedarIcon. The original black placeholder asset is retained. Version 0.4.1 uses build 6.

[GitHub Actions run 44960935722](https://github.com/harshitgupta1998/cedar/actions/runs/44960935722) passed the simulator build and existing test suite. After the user approved signing-key access, the signed device build succeeded. Cedar 0.4.1 (build 6) was installed on the iPhone 13, verified through the device application inventory, and launched successfully. The compiled primary icon references the new CedarIcon asset. Work continued from a fresh checkout at ~/Projects/cedar because macOS denied access to the earlier Documents checkout.

## Recovery, summary quality and usability — 0.5.0, November 22, 2026

Recording metadata now has a valid previous-manifest backup. Corrupt or missing manifests no longer hide retained audio. Damaged metadata is preserved before repair, and failed repair writes leave recordings visible. Active captures are protected from recovery and stale delete requests. The Stop control stays available during active capture. Unreadable audio can be retried explicitly and is preserved if it remains unreadable.

Damaged transcript and notes files can recover their latest valid archived revision with a visible notice. Notes can be edited, copied, shared and restored from a previous version. Edits retain the source transcript identity. Empty and stale concurrent edits are rejected. Model downloads report progress, support cancellation/retry, and clean up uncommitted staging after app termination.

The 360M prompt improved from 4/7 to 6/7 synthetic checks. Qwen3 1.7B Q4_K_M passed 7/7 main and 4/4 additional checks in the recorded Mac evaluation. The larger model uses a pinned 1.11 GB download, SHA-256 verification, its published non-thinking template, a 2,048-token context and a 1,600-token prompt budget. A memory preflight runs on physical devices. Model selection is explicit. See [the evaluation and its limitations](../evaluation/README.md).

All 34 local unit/integration tests passed, including three real-audio interruption-handler tests and real inference for both models in the simulator. All seven UI cases passed; an additional run verified notes persistence, editing, restoration, copy feedback and presentation of the iOS share sheet. Screenshots from that run were reviewed. The signed device build passed and Cedar 0.5.0 (build 7) installed. Physical larger-model inference and final CI are pending.

The user confirmed that the saved 00:21 clip played correctly and that recording had stopped. The user explicitly identified it as a quick test. The 30-minute locked-screen test remains unverified.
