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

Local validation: all five storage tests passed. Welcome navigation and the full recording → restore UI flow passed on the iPhone 13 / iOS 26.5 simulator.

## Physical device evidence

November 8, 2026: Cedar 0.2.0 installed and launched on the iPhone 13 with iOS 26.5.2. The user confirmed a spoken recording, approximately 15 seconds with the phone locked, stop/save, and complete audible playback, including the locked-screen portion.

This short smoke test does not establish the full recording reliability gate.

## Remaining device checks

- [ ] A 30-minute locked-screen recording plays end to end.
- [ ] Airplane-mode capture and playback work.
- [ ] Incoming call / Siri / alarm interruptions preserve the earlier audio and show a stopped state.
- [ ] Relaunch after force-closing during a real microphone recording recovers the available audio.
- [ ] Microphone denial shows the Settings path without affecting the library.
- [ ] Low-storage and write-failure behavior on a disposable test device or test volume.
- [ ] VoiceOver, larger Dynamic Type, and landscape pass.

## Current limits

Recently Deleted is retained indefinitely on this device and can be restored. Permanent purge and export are not yet implemented. Unreadable or corrupt recordings are preserved for investigation; Cedar cannot promise that every partial file is repairable. Disabling microphone permission affects future capture, not already-saved playback. Device uninstall removes the app sandbox, including recordings; this version has no cloud backup.

## Platform references

- [Apple: audio recording category and background capture](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)
- [Apple: audio interruptions](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionnotification)
- [Apple: microphone permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication)
