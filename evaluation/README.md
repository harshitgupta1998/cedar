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

## Reproduce

Run `python3 scripts/setup-inference.py`. Obtain the model file from the pinned URL in `ios/Cedar/NotesModel.swift`; the engine verifies its size and SHA-256. Compile the same engine used by the app:

```sh
mkdir -p build-evaluation
swiftc -O -parse-as-library \
  -F ios/Vendor/llama.xcframework/macos-arm64_x86_64 -framework llama \
  -Xlinker -rpath -Xlinker "$PWD/ios/Vendor/llama.xcframework/macos-arm64_x86_64" \
  ios/Cedar/LocalNotesEngine.swift ios/Cedar/NotesModel.swift \
  ios/Cedar/LocalNotes.swift ios/Cedar/Transcript.swift scripts/evaluate-notes.swift \
  -o build-evaluation/evaluate-notes

build-evaluation/evaluate-notes evaluation/notes-cases.json \
  /path/to/model.gguf build-evaluation/results.json qwen17
```

Use `smol360` for the compact model. Use `evaluation/notes-holdout.json` for the additional fixtures. The script reports check failures and model errors while retaining every output for review.

## Sources

- [SmolLM2 360M model and Apache 2.0 license](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct)
- [Qwen3 1.7B model, Apache 2.0 license and non-thinking template](https://huggingface.co/Qwen/Qwen3-1.7B)
- [Pinned Qwen3 Q4_K_M conversion](https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/tree/d7f544eead698dbd1f15126ef60b45a1e1933222)
