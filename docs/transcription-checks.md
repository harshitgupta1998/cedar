# On-device transcription — Cedar 0.3.0

## Current behavior

Open a saved recording, choose Transcript and a language, then tap Transcribe recording. Speech Recognition permission is requested at that point. Checking support does not start recognition or request microphone access.

Cedar selects an available on-device engine at runtime:

1. On iOS 26 with Xcode 26-built code, prefer SpeechTranscriber through SpeechAnalyzer.
2. Otherwise try DictationTranscriber through SpeechAnalyzer for supported older hardware/languages.
3. Where those engines are unavailable, use SFSpeechRecognizer only if `supportsOnDeviceRecognition` is true, with `requiresOnDeviceRecognition = true`. This fallback is limited to 55-second clips and has a two-minute request timeout.
4. If no local engine is supported, show an unavailable message. There is no cloud recognition fallback.

A language-model download is offered explicitly when needed. It downloads Apple's model; it does not upload the recording. Model support and installation are rechecked before recognition. Keep Cedar open during processing; leaving the transcript screen cancels the task.

## Storage and recovery

- Audio remains separate and unchanged in `audio.caf`.
- Only a successful, finalized transcript is committed to `transcript.json` in the recording's directory.
- Each segment has an ID, start/end milliseconds, and editable text. Timestamps are recognition-segment ranges, not a promise of word-level alignment.
- Edits retain the source timestamps and increment the transcript revision.
- Replacing a saved transcript first archives its prior revision in `TranscriptRevisions`. A failure to archive stops replacement.
- Cancellation, permission denial, recognition failure, or no detected speech keeps the audio and any earlier saved transcript.
- Moving a recording to Recently Deleted and restoring it carries its transcript and revision files with it.
- Transcript files and archives use iOS Data Protection, complete until first user authentication.
- Capability diagnostics store OS, language, engine and readiness only; they do not contain recognized text or audio.

## Verified on iPhone 13 — November 9, 2026

Device: iOS 26.5.2. The device's capability report selected `speechAnalyzer` with locale `en_US` and the language model already installed.

The user confirmed:

- A fresh short spoken recording produced a transcript.
- A fresh recording transcribed with Airplane Mode enabled and Wi-Fi off.
- Editing a word, saving, closing and reopening Cedar retained the edit.

No private transcript text or audio was added to the public repository.

## Automated checks

Nine new model/controller tests use deterministic provider results to verify successful persistence, cancellation including late completion, denied permission, no speech, short-fallback duration enforcement, model download without automatic recognition, edit/timestamp preservation, revision archiving, trash/restore, invalid-document rejection, and archive-write failure preservation.

All fifteen hardware-independent storage/controller tests passed. Six UI regression cases have passing runs. The six original storage tests remain in the hardware-independent suite. UI regression checks cover the recorder and library, plus opening Transcript to check capabilities without requesting recognition permission and returning to playable audio. These tests do not establish recognition accuracy; the actual iPhone checks above supply the short-clip speech evidence.

## Still to validate

- 10- and 30-minute transcription on the actual iPhone, processing time and cancellation during long input.
- Physical-device model download, a second language, unavailable-locale behavior, and speech-permission denial.
- Physical validation of DictationTranscriber and the legacy fallback; this iPhone selected SpeechTranscriber.
- Recognition quality across noise, multiple speakers, accents, and silence.
- Playback/edit UI with larger transcripts, VoiceOver and the largest Dynamic Type sizes.
- The independently deferred 30-minute locked-screen capture check remains open.

The previous-revision files are retained locally, but a revision-history restore UI and permanent purge are not implemented. No summaries, memory search, cloud synchronization or AI backend are implemented in this version.

## Primary references

- [Apple: SpeechAnalyzer overview and on-device model strategy](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple: runtime availability checks](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Apple: local-only legacy requests](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
