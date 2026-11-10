# Local recording verification

## Implemented

- Explicit microphone permission on the first Record tap, with a Settings path when denied.
- Recording timer and microphone level; Stop & save returns a playable local item.
- UUID directory and atomic JSON manifest created before capture starts.
- Mono 16 kHz, 16-bit linear PCM in CAF (about 1.9 MB per minute).
- Audio and manifests use iOS Data Protection: complete until first user authentication.
- Background audio configuration; recording can continue when the screen locks.
- Playback, pause, seeking, rename, Recently Deleted, and restore.
- An audio interruption or disconnected audio device stops recording and retains available audio; Cedar does not automatically restart the microphone.
- Unfinished recording manifests are reconciled on launch. Readable audio is marked Recovered; unreadable audio is retained and marked for recovery. A corrupt manifest raises a library warning without deleting the source folder.
- No network services, transcription, audio uploads, analytics, or cloud backup are implemented.

## Automated checks

Storage tests generate a one-second tone and verify save/relaunch, duration, rename, recoverable deletion/restore, recovery after an unfinished manifest, preservation of unreadable audio, and preservation of audio with corrupt metadata. They also reject blank names and deletion while recording.

UI tests use an isolated library selected by `--test-store <UUID>`, honored only in Debug simulator builds. They cover welcome navigation and a short recording → stop/save → relaunch → playback/pause/seek → rename → delete/restore flow. Audio capture tests require an available simulator microphone input. GitHub Actions runs the hardware-independent storage tests.

Initial validation on November 8: all five original storage tests passed. Welcome navigation and the full recording → restore UI flow passed on the iPhone 13 / iOS 26.5 simulator.

## Physical device evidence

November 8, 2026: Cedar 0.2.0 installed and launched on the iPhone 13 with iOS 26.5.2. The user confirmed short spoken capture and audible playback. Metadata inspected November 9 shows that saved clip is 3.10 seconds; this does not establish a sustained locked-screen test.

This short smoke test does not establish the full recording reliability gate.

## Remaining device checks

- [ ] A 30-minute locked-screen recording plays end to end.
- [x] Airplane-mode capture and playback work (user-confirmed November 9; saved duration 9.68 seconds).
- [ ] Incoming call / Siri / alarm interruptions preserve the earlier audio and show a stopped state.
- [ ] Relaunch after force-closing during a real microphone recording recovers the available audio.
- [ ] Microphone denial shows the Settings path without affecting the library.
- [ ] Low-storage and write-failure behavior on a disposable test device or test volume.
- [x] Largest Dynamic Type and landscape controls pass in the iPhone 13 simulator.
- [ ] VoiceOver and a physical-device accessibility spot check pass.

## Current limits

Recently Deleted is retained indefinitely on this device and can be restored. Permanent purge and export are not yet implemented. Unreadable or corrupt recordings are preserved for investigation; Cedar cannot promise that every partial file is repairable. Disabling microphone permission affects future capture, not already-saved playback. Device uninstall removes the app sandbox, including recordings; this version has no cloud backup.

## Platform references

- [Apple: audio recording category and background capture](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)
- [Apple: audio interruptions](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification)
- [Apple: microphone permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication)

## Reliability checks — November 9, 2026

- Simulator capture → force-quit before Stop → relaunch → Recovered → playback: passed.
- Simulator microphone denial: Settings guidance appears; capture stays stopped; saved playback remains available.
- Controller integration tests capture real simulator audio, inject interruption/input-disconnect/audio-service-reset notifications, and confirm playable retained audio and no automatic microphone restart. All three passed. These do not substitute for a real phone call, Siri, or alarm interruption.
- A sixth storage test forces the atomic manifest write to fail, confirms the original audio is unchanged, then restores writable metadata and verifies relaunch recovery. Passed.
- The largest Dynamic Type size exposed a fixed-footer space problem. In accessibility text sizes and compact-height layouts, the consent reminder now scrolls with the library while Record remains pinned.
- Audio integration tests require a simulator with microphone access already granted. CI explicitly excludes those hardware-dependent tests and runs the six storage tests. UI tests skip physical devices to keep personal device libraries separate from test fixtures.

Final local checks: all nine controller/storage tests and all five UI tests passed. The largest accessibility text size was also tested in portrait and landscape, with full-screen screenshots reviewed. The signed iOS 0.2.1 build passed.

The user confirmed offline capture and playback on November 9. Read-only inspection of the saved manifest established a 9.68-second clip (displayed as 00:09). Only metadata was copied for this check; the audio stayed on the phone. A 30-minute locked-screen recording and a real-device interruption result remain unverified, so the recording reliability gate stays open.
