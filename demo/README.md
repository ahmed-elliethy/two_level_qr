# TwoLevelQR CLI Demo

A terminal-based test and demonstration harness for the `two_level_qr` SDK.
It runs automated suites, renders QR codes in the terminal, and includes an
interactive menu for exploring both the standard QR pipeline and the keyed
two-level QR hidden-message channel.

## Installation

Make sure you have the Dart SDK installed, then run:

```bash
cd demo
dart pub get
```

The CLI depends on the `two_level_qr` package via a local path dependency.

## Running the full verification suite

```bash
dart run bin/main.dart --suite
```

This executes:

1. **Mathematical Foundations & Pure Services** — GF(256), Reed-Solomon, BCH,
   bit-stream codec, block interleaver, masking, matrix renderer.
2. **End-to-End Stress Tests** — standard payload roundtrips, randomized
   stress tests, and Reed-Solomon self-healing with injected noise.
3. **Keyed Two-Level QR Hidden Message Channel** — roundtrip, wrong-key
   garbage, standard-scanner compatibility, different keys, UTF-8 secrets,
   noise + hidden errors, capacity overflow, and ratio mismatch.

## Encoding a two-level QR with a hidden message

```bash
dart run bin/main.dart \
  --hidden-encode "https://example.com/public-info" \
  --hidden-text "SECRET_KEY_12345" \
  --key "my-secret-key" \
  --level H \
  --ratio 0.8
```

Flags:

- `--hidden-encode` — public QR payload
- `--hidden-text` — secret message to hide (default `SECRET_KEY_12345`)
- `--key` — secret key controlling error positions (default `my-secret-key`)
- `--ratio` — fraction of RS error budget used for hidden data (default `0.8`)
- `--level` — error correction level: `L`, `M`, `Q`, or `H` (default `H`)
- `--version` — optional explicit QR version (disables auto-bumping)
- `--mask` — optional explicit mask pattern `0..7`

The encoder prints the QR matrix to the terminal and verifies both the public
and hidden payloads decode correctly.

If the hidden message is too large even for QR version 40, a meaningful
`HiddenMessageCapacityException` is printed, showing the payload size and the
maximum available capacity.

## Hidden-message demo

Run a self-contained demonstration that:

- Encodes a public + hidden payload
- Prints the QR matrix
- Decodes with the correct key
- Decodes with a wrong key to show garbage output
- Runs a standard QR decode to prove scanners only see the public payload

```bash
dart run bin/main.dart --hidden-demo
```

## Interactive menu

Launch the interactive harness with no arguments:

```bash
dart run bin/main.dart
```

Available options include:

- `[1]` Step-by-step pipeline stage stepper
- `[2]` Full verification suite
- `[3]` Encode custom text to terminal QR
- `[4]` Inspect pipeline checkpoints
- `[5]` Reed-Solomon damage & recovery demo
- `[6]` Performance benchmarks
- `[7]` Keyed two-level QR hidden-message demo
- `[0]` Exit

## Other commands

### Standard encode

```bash
dart run bin/main.dart --encode "https://example.com" --level H
```

### Inspect pipeline checkpoints

```bash
dart run bin/main.dart --inspect "Hello TwoLevelQR"
```

### Reed-Solomon self-healing demo

```bash
dart run bin/main.dart --corrupt-demo
```

### Performance benchmarks

```bash
dart run bin/main.dart --bench
```

### Pipeline stage stepper

```bash
dart run bin/main.dart --pipeline-step "Stage Test" --level H --flips 6
```

## Project structure

```
demo/
├── bin/main.dart                 # CLI entry point and argument parsing
├── lib/
│   ├── benchmarks/
│   │   └── benchmark_runner.dart # Performance benchmarks
│   ├── demos/
│   │   ├── checkpoint_inspector.dart
│   │   ├── corruption_demo.dart
│   │   ├── hidden_message_demo.dart
│   │   └── pipeline_stage_stepper.dart
│   ├── suites/
│   │   ├── e2e_stress_tests.dart
│   │   ├── hidden_message_tests.dart
│   │   └── math_and_codec_tests.dart
│   └── terminal_utils.dart       # Terminal rendering & formatting
└── pubspec.yaml
```

## License

MIT
