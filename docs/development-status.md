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

All 34 local unit/integration tests passed, including three real-audio interruption-handler tests and real inference for both models in the simulator. All seven UI cases passed; an additional run verified notes persistence, editing, restoration, copy feedback and presentation of the iOS share sheet. Screenshots from that run were reviewed. The signed device build passed and Cedar 0.5.0 (build 7) installed. The final ten storage/recovery tests were rerun after the unreadable-audio retry change and passed. [GitHub Actions run 45045174076](https://github.com/harshitgupta1998/cedar/actions/runs/45045174076) passed: 29 tests passed and two optional real-model tests were skipped because CI does not install weights.

The physical iPhone 13 test reached the engine but rejected Qwen3 at its memory preflight (`insufficientMemory`) before loading weights. Simulator inference and Mac quality results therefore do not establish iPhone 13 compatibility. The user subsequently confirmed the same insufficient-memory error in the regular app. The normal signed app was reinstalled and launched after the test; the verified larger model remains installed. SmolLM2 360M remains the default and has previously worked on this phone.

The user confirmed that the saved 00:21 clip played correctly and that recording had stopped. The user explicitly identified it as a quick test. The 30-minute locked-screen test remains unverified.

## Smaller model and long-transcript processing — 0.6.0, November 22, 2026

The user requested removal of both existing models after Qwen3 1.7B failed with insufficient app memory. Qwen3 0.6B Q4_K_M is now the sole downloadable option: 397 MB, Apache 2.0, pinned revision and SHA-256. Both retired weights are removed at launch, with retry feedback on deletion failure. Existing audio, transcripts, notes and revisions remain. A read-only device listing confirmed that only the new weights remained after launch.

Long transcripts are split against the actual tokenizer, with 1,000 prompt tokens, at most 384 output tokens and a fixed 1,536-token context per section. The model/context load once, cache resets per section, and progress shows the current section. Source words are included once without truncation. Limits are 16,000 words, 180,000 characters and 64 sections. Notes follow transcript order, so later sections may revise earlier decisions. No global synthesis is performed. Cancelled/failed runs retain existing saved notes rather than publishing partial notes. The screen stays awake during notes and transcription processing; prior idle settings are restored at completion/cancellation.

The initial 39 local unit/integration tests passed. After the final prompt/context changes, 14 notes/editing tests passed with the separate physical-hour case skipped on simulator. All nine transcription tests and the notes editing/restoration/copy/share UI case passed after adding screen-awake handling; the transcription tests verify idle-setting restoration. Final signed device build passed, and Cedar 0.6.0 (build 8) was reinstalled and launched after the automated tests. The user confirmed that the regular app saved notes labeled Qwen3 0.6B without a memory error. [GitHub Actions run 45046974936](https://github.com/harshitgupta1998/cedar/actions/runs/45046974936) subsequently passed.

Both actual iPhone 13 tests passed with Qwen3 0.6B: the 9,141-word synthetic transcript completed in 14 sections in 48.7 seconds without a memory error, and the short conditional-proposal case completed in 9.7 seconds. This is text equivalent to about an hour at 150 words/minute, not an hour-long recording. The 11 short Mac regression checks passed. The long output still omitted pending status and introduced an unsupported agreement to review; it does not pass the full fact-quality checks. See [raw results and limitations](../evaluation/README.md).

The end-to-end hour-long recording → transcription → notes check, thermal/battery measurement and real-conversation quality remain unverified. The earlier 30-minute capture test remains deferred.

## Summary and actionable insights — 0.7.0, November 22, 2026

Notes now have an overall Summary, source-backed Action items, and Suggested follow-ups labeled as questions rather than commitments. Each action shows source excerpts and owner/due fields, with missing values left unspecified. Exact source checks and conservative condition/completion/negation rules omit unsupported generated items with a review notice. Explicit named future commitments and short personal reminders can be retained directly from source when the model misses them.

Long model-written summaries copied passages and introduced unsupported conclusions in development. The final long-summary path uses a labeled selection of complete source statements, prioritized by decisions, named tasks and unresolved issues. Selection is bounded and preserves source order. It still needs review for omissions and later corrections; it does not establish semantic accuracy. Short model-written summaries remain in use. Structured extraction sees each full source section, with a fixed 1,536-token context and budgets of 900 prompt/600 output tokens.

The release adds source/evidence/metadata checks and structured-output evaluation cases. Forty hardware-independent/real-audio tests plus a skipped physical-only case passed locally, and the existing notes edit/restore/copy/share UI check passed. The signed 0.7.0 (build 9) app was installed and launched. Nineteen short model checks passed (eight action-specific, seven main and four additional), plus the longer meeting regression. The final Mac hour-equivalent case completed in 39.9 seconds. The physical structured-pipeline hour case completed in 191.1 seconds, and its short case in 15.1 seconds, before final deterministic overview/temporal-field refinements; see the evaluation for scope. The user confirmed that regenerated notes in the regular iPhone app show Summary, source-backed Action items and Suggested follow-ups as separate sections. [Release CI](https://github.com/harshitgupta1998/cedar/actions/runs/45052292344) is queued.

## Library tools — 0.8.0 feature branch, November 22, 2026

Branch `codex/source-search-actions` adds local phrase search across titles/transcripts/notes, matched-source playback from notes, and a persistent per-recording action checklist. Search is debounced, cancellable and performed off the main thread, with per-document memory cleanup and a 32 MB document cap. Deleted recordings are excluded. Unreadable text produces a partial-results notice. No index is uploaded or persisted.

Source excerpts and literal summary statements resolve against the saved transcript, including matches spanning segments and multiple occurrences. Playback starts at the corresponding segment; no word-level precision is claimed. Paraphrases are not linked. Notes from an older transcript revision disable playback until regeneration. Resolved matches are cached between playback progress updates.

Users explicitly add extracted actions or create tasks manually, edit task details and complete/reopen tasks. Exact repeated imports retain the existing task and its completion state. Notes edits/regeneration do not replace the checklist. Tasks survive recording trash/restore. Metadata edits remove generated source attribution, stale transcript provenance is flagged, concurrent edits are rejected, and invalid checklist files are retained rather than overwritten. Due is a text field; there is no Reminders/calendar integration.

All 45 selected local unit/integration tests passed, including three real-audio handler tests; one physical-only model case was skipped. The existing notes editing/restore/copy/share UI regression passed. The new UI flow passed search and empty-result handling, source playback at 00:02, task import/completion, relaunch persistence and editing. Default-text portrait/landscape controls passed separately. Explicit largest-text coverage was added in the 0.9.0 follow-up below. The completed-task screenshot was reviewed. The signed device build passed. The AI model/prompt pipeline was not changed; real-model inference tests were excluded from this UI/storage-focused run. The source-match cache UI rerun passed, as did the final checklist/storage tests and signed build after clearer damaged-file errors. Branch publication and CI are tracked in the draft pull request. Physical interaction checks and a large-library performance benchmark remain open.

## Transcript navigation — 0.9.0 feature branch, November 22, 2026

PR #1 merged as `75ffd00` after its GitHub checks passed. New work is on `codex/transcript-navigation`.

Saved transcripts now have a persistent find field, case/accent-insensitive phrase matching within individual segments, emphasized matching text, previous/next controls with wraparound, and a play-selected-match action. Counts describe matching segments, not word occurrences. Empty or pending results disable playback/navigation actions. Start returns to the beginning. A bottom playback bar provides pause/resume and elapsed/duration. Search is debounced, cancellable and performed off the main thread; highlighted text is cached. Saved-transcript revisions invalidate pending results. Typing does not start audio and no search state is uploaded or persisted.

Saved transcripts collapse transcription setup into Transcription options so notes and transcript content remain reachable below the find panel. The selected row is repositioned when the player appears so its text remains visible. Player errors are shown. Previous/next expose result-position accessibility values. Manual VoiceOver and physical-device interaction checks remain open.

All 47 selected local unit/integration tests passed, with one physical-only case skipped. Model-dependent cases were excluded because the inference pipeline was unchanged. New tests cover Unicode-preserving emphasis, segment-vs-occurrence counts, hour-length synthetic transcript search and cancellation. The new UI case passed matching counts, next/previous wrapping, scrolling to 00:06, playback/pause, no-result disabling, clear and return-to-start. Source playback/checklist persistence and transcription-capability UI regressions passed after collapsing setup controls. Default-text library portrait/landscape controls and an explicitly requested largest-accessibility-text portrait/landscape case passed. Initial rotation attempts left the simulator in portrait; a clean simulator restart resolved this, with screen captures checked. The earlier layout check had used the default text size; its coverage wording above is corrected. The signed iPhone build passed.
