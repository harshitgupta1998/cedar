# Local summary evaluation

These synthetic fixtures check decisions, owners, dates, corrected numbers, negation, conditional assignments and quoted instructions. They contain no personal recordings or transcripts.

## November 22, 2026 results

| Model | Main fixtures | Additional fixtures | Prompt | Context |
| --- | --- | --- | --- | --- |
| SmolLM2 360M Q4_K_M (0.4.1 prompt) | 4/7 | Not run | baseline | 4,096 |
| SmolLM2 360M Q4_K_M | 6/7 | 4/4 | faithful-v2 | 4,096 |
| Qwen3 1.7B Q4_K_M | 7/7 | 4/4 | faithful-v3, non-thinking | 2,048 |

The 360M model incorrectly treated an example instruction about cancelling a meeting as an actual cancellation. Qwen3 preserved the actual Tuesday meeting decision and the conditional assignment in the tested outputs. Qwen2.5 1.5B was also explored, but its tested output strengthened “might” to “will” and mishandled the quoted instruction, so it was not retained as an app option.

The additional fixture source texts were defined before the final prompt revision. One forbidden-phrase check originally matched the valid phrase “no replacement was approved.” That check was corrected to match a full affirmative claim. The generated text was reviewed as well as checked by the script.

These are small, English synthetic regression checks with string matching. Passing them does not establish factual accuracy on real conversations. The checks can miss incorrect paraphrases and flag valid ones. Read the saved outputs in `results/` when comparing changes. Summaries remain experimental and editable.

The runs used macOS, Metal and llama.cpp b9000 with greedy sampling. Models were released after each case. Timing includes model verification and loading. Kernel/file caches were warm for many cases. These timings and process-wide peak resident measurements describe the Mac test process. They do not measure iPhone latency, battery use, or memory requirements. Peak Mac resident memory was about 0.73 GiB for 360M and 2.38 GiB for Qwen3 in these runs.

## Replacement model and hour-length text — 0.6.0

After the user confirmed insufficient app memory for Qwen3 1.7B in the regular iPhone app, it and SmolLM2 360M were replaced by Qwen3 0.6B Q4_K_M. The 396,705,472-byte pinned conversion is Apache 2.0. Both retired weight files are removed on launch; generated documents remain.

The final `sections-v4/non-thinking` prompt passed 7/7 main and 4/4 additional short fixtures. Short input keeps the faithful summary prompt; multi-section input adds a reminder after each section to prioritize concrete facts over repeated discussion. The initial long prompt omitted several named facts in repeated text. A smaller 1,000-token prompt budget and the final reminder improved retention. These fixtures informed development, so they are regression checks rather than an independent accuracy estimate.

The long fixture is deterministically generated in `scripts/evaluate-long-notes.swift`. Its 9,141 words correspond to about 61 minutes at 150 spoken words/minute. It deliberately repeats filler around nine named facts. All source words are processed once through 14 bounded sections; a separate 10,800-word unit test verifies exact source coverage. The model and fixed 1,536-token context remain loaded once; cache is cleared between sections. Notes keep each chronological section, with no final synthesis that could hide later sections or silently drop details.

| Final run | Completion | Sections | Time |
| --- | --- | --- | --- |
| Mac / Metal | Completed | 14 | 8.4 seconds |
| iPhone 13 / iOS 27.2.1 / Metal / XCTest | Completed without memory error | 14 | 48.7 seconds |

The physical-device short case also completed in 9.7 seconds and preserved the pending proposal and conditional assignment. Runtime and caches were warm for portions of these runs. They are single measurements, not latency guarantees. `getrusage` resident-memory values are included in raw reports, but do not measure the full Metal allocation footprint or establish safe device memory requirements. Do not compare the iPhone value directly with the Mac value as total app memory.

**Known long-output quality failure:** both final hour-length outputs omitted the explicit word/status “pending.” Section 11 also says the meeting “agreed to review the proposal,” which is unsupported, although it separately retains “Sam might review ... if approved.” The long benchmark's full fact checks therefore fail; successful completion and early/middle/end anchors do not establish factual fidelity. Some repetitive filler remains in the notes. The raw outputs are retained in `results/qwen06-hour-*.json` so these failures are reviewable. Cross-section corrections and real conversational detail need further evaluation.

This tests synthetic text, not an hour of real audio. Actual sustained recording, hour-long speech recognition, battery/thermal behavior, manual background interruptions, and real-conversation note quality remain open.

## Reproduce

Run `python3 scripts/setup-inference.py`. Obtain the model from the pinned URL in `ios/Cedar/NotesModel.swift`; the engine verifies size and SHA-256. Compile the app's engine on an Apple Silicon Mac:

```sh
mkdir -p build-evaluation
swiftc -O -parse-as-library \
  -F ios/Vendor/llama.xcframework/macos-arm64_x86_64 -framework llama \
  -Xlinker -rpath -Xlinker "$PWD/ios/Vendor/llama.xcframework/macos-arm64_x86_64" \
  ios/Cedar/LocalNotesEngine.swift ios/Cedar/NotesModel.swift \
  ios/Cedar/LocalNotes.swift ios/Cedar/Transcript.swift scripts/evaluate-notes.swift \
  -o build-evaluation/evaluate-notes

build-evaluation/evaluate-notes evaluation/notes-cases.json \
  /path/to/Qwen3-0.6B-Q4_K_M.gguf build-evaluation/results.json qwen06
```

Use `evaluation/notes-holdout.json` for additional fixtures. For the long benchmark, compile with `scripts/evaluate-long-notes.swift` instead of `scripts/evaluate-notes.swift`, then run `evaluate-long-notes model.gguf report.json`. It exits unsuccessfully if a checked named fact is absent while retaining the complete report. The actual-device XCTest covers completion, section coverage and endpoint anchors and records all missing fact checks separately; its pass is not an accuracy pass.

Historical 360M/1.7B results above refer to earlier source commits, not the current model configuration.

## Sources

- [SmolLM2 360M model and Apache 2.0 license](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct)
- [Qwen3 1.7B model, Apache 2.0 license and non-thinking template](https://huggingface.co/Qwen/Qwen3-1.7B)
- [Pinned Qwen3 Q4_K_M conversion](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/tree/d7f544eead698dbd1f15126ef60b45a1e1933222)

- [Qwen3 0.6B model, license and non-thinking template](https://huggingface.co/Qwen/Qwen3-0.6B)
- [Pinned Qwen3 0.6B conversion](https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/tree/50968a4468ef4233ed78cd7c3de230dd1d61a56b)
