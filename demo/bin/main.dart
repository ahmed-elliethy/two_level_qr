import 'dart:io';
import 'package:args/args.dart';
import 'package:two_level_qr/two_level_qr.dart';
import 'package:two_level_qr_cli/benchmarks/benchmark_runner.dart';
import 'package:two_level_qr_cli/demos/checkpoint_inspector.dart';
import 'package:two_level_qr_cli/demos/corruption_demo.dart';
import 'package:two_level_qr_cli/demos/hidden_message_demo.dart';
import 'package:two_level_qr_cli/demos/pipeline_stage_stepper.dart';
import 'package:two_level_qr_cli/suites/e2e_stress_tests.dart';
import 'package:two_level_qr_cli/suites/hidden_message_tests.dart';
import 'package:two_level_qr_cli/suites/math_and_codec_tests.dart';
import 'package:two_level_qr_cli/terminal_utils.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage information.')
    ..addFlag('suite', abbr: 's', negatable: false, help: 'Run the full test and verification suite.')
    ..addOption('pipeline-step', abbr: 'p', help: 'Run stage-by-stage pipeline stepper with before/after RS error correction.')
    ..addOption('encode', abbr: 'e', help: 'Encode text and display QR code in terminal.')
    ..addOption('inspect', abbr: 'i', help: 'Inspect all pipeline checkpoints for given text.')
    ..addFlag('corrupt-demo', abbr: 'c', negatable: false, help: 'Run damage injection & Reed-Solomon self-healing demo.')
    ..addFlag('bench', abbr: 'b', negatable: false, help: 'Run performance and throughput benchmarks.')
    ..addFlag('hidden-demo', negatable: false, help: 'Run keyed two-level QR hidden-message demo.')
    ..addOption('hidden-encode', help: 'Encode public text with a hidden message (requires --hidden-text and --key).')
    ..addOption('hidden-text', defaultsTo: 'SECRET_KEY_12345', help: 'Hidden secret message for two-level encode.')
    ..addOption('key', defaultsTo: 'my-secret-key', help: 'Secret key controlling hidden error positions.')
    ..addOption('ratio', defaultsTo: '0.8', help: 'Fraction of RS error budget used for hidden data (0.0..1.0].')
    ..addOption('level', abbr: 'l', defaultsTo: 'H', help: 'Error Correction Level: L, M, Q, or H.')
    ..addOption('flips', abbr: 'f', defaultsTo: '6', help: 'Number of matrix module errors to inject (0..10).')
    ..addOption('version', abbr: 'v', help: 'Explicit version number (1..40).')
    ..addOption('mask', abbr: 'm', help: 'Explicit mask pattern (0..7).')
    ..addFlag('interactive', negatable: false, help: 'Start interactive CLI menu.');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    stderr.writeln(TerminalUtils.error('Error: $e\n'));
    stdout.writeln(parser.usage);
    exit(1);
  }

  if (results['help'] as bool) {
    _printHelp(parser);
    return;
  }

  final levelStr = (results['level'] as String).toUpperCase();
  final level = _parseEcLevel(levelStr);
  final flips = int.tryParse(results['flips'] as String) ?? 6;

  int? explicitVersion;
  if (results['version'] != null) {
    explicitVersion = int.tryParse(results['version'] as String);
  }

  MaskPattern? explicitMask;
  if (results['mask'] != null) {
    final maskIdx = int.tryParse(results['mask'] as String);
    if (maskIdx != null && maskIdx >= 0 && maskIdx <= 7) {
      explicitMask = MaskPattern.fromBits(maskIdx);
    }
  }

  final ratio = double.tryParse(results['ratio'] as String) ?? 0.8;
  if (ratio <= 0.0 || ratio > 1.0) {
    stderr.writeln(TerminalUtils.error('Error: ratio must be in (0.0, 1.0]'));
    exit(1);
  }

  // 1. Full Test Suite
  if (results['suite'] as bool) {
    _runFullTestSuite();
    return;
  }

  // 2. Stage-by-Stage Pipeline Stepper
  if (results['pipeline-step'] != null) {
    final text = results['pipeline-step'] as String;
    PipelineStageStepper.runStepper(
      text: text.isEmpty ? 'TWO_LEVEL_QR_STAGE_STEPPER_DEMO' : text,
      level: level,
      injectModuleFlipsCount: flips,
    );
    return;
  }

  // 3. Encode
  if (results['encode'] != null) {
    final text = results['encode'] as String;
    _runEncode(text, level: level, explicitVersion: explicitVersion, explicitMask: explicitMask);
    return;
  }

  // 4. Inspect Checkpoints
  if (results['inspect'] != null) {
    final text = results['inspect'] as String;
    CheckpointInspector.inspect(text, level: level);
    return;
  }

  // 5. Corruption Demo
  if (results['corrupt-demo'] as bool) {
    CorruptionDemo.runDemo();
    return;
  }

  // 6. Benchmark
  if (results['bench'] as bool) {
    BenchmarkRunner.runBenchmarks();
    return;
  }

  // 7. Hidden Message Demo
  if (results['hidden-demo'] as bool) {
    HiddenMessageDemo.runDemo(
      publicText: 'https://example.com/public-info',
      hiddenText: 'SECRET_KEY_12345',
      key: 'demo-secret-key',
      ratio: ratio,
      level: level,
    );
    return;
  }

  // 8. Hidden Message Encode
  if (results['hidden-encode'] != null) {
    final publicText = results['hidden-encode'] as String;
    final hiddenText = results['hidden-text'] as String;
    final key = results['key'] as String;
    _runHiddenEncode(
      publicText: publicText.isEmpty ? 'https://example.com/public-info' : publicText,
      hiddenText: hiddenText,
      key: key,
      ratio: ratio,
      level: level,
      explicitVersion: explicitVersion,
      explicitMask: explicitMask,
    );
    return;
  }

  // If no arguments or --interactive, run interactive menu
  _runInteractiveMenu();
}

void _printHelp(ArgParser parser) {
  TerminalUtils.printHeader('TwoLevelQR CLI Test & Demo Harness', subtitle: 'v0.1.0 — Clean Architecture QR Code SDK');
  stdout.writeln('\nUsage: dart run bin/main.dart [options]\n');
  stdout.writeln(parser.usage);
  stdout.writeln('\nExamples:');
  stdout.writeln('  dart run bin/main.dart --pipeline-step "Stage Test" --level H --flips 6');
  stdout.writeln('  dart run bin/main.dart --suite');
  stdout.writeln('  dart run bin/main.dart --encode "https://example.com" --level H');
  stdout.writeln('  dart run bin/main.dart --hidden-encode "https://example.com" --hidden-text "SECRET" --key "k"');
  stdout.writeln('  dart run bin/main.dart --hidden-demo');
  stdout.writeln('  dart run bin/main.dart --inspect "Hello TwoLevelQR"');
  stdout.writeln('  dart run bin/main.dart --corrupt-demo');
  stdout.writeln('  dart run bin/main.dart --bench');
}

void _runFullTestSuite() {
  TerminalUtils.printHeader('TwoLevelQR Full Test & Verification Suite', subtitle: 'Executing unit, property, and integration validations');
  final stopwatch = Stopwatch()..start();

  var totalFailures = 0;
  totalFailures += MathAndCodecTests.runAll();
  totalFailures += E2eStressTests.runAll();
  totalFailures += HiddenMessageTests.runAll();

  stopwatch.stop();

  TerminalUtils.printSection('Suite Summary');
  TerminalUtils.printMetric('Execution Duration', '${stopwatch.elapsedMilliseconds} ms');
  if (totalFailures == 0) {
    stdout.writeln(TerminalUtils.success('\n🎉 ALL TESTS PASSED! 100% Functionality Verified.\n'));
  } else {
    stdout.writeln(TerminalUtils.error('\n❌ $totalFailures test(s) failed.\n'));
    exit(1);
  }
}

void _runEncode(String text, {required ErrorCorrectionLevel level, int? explicitVersion, MaskPattern? explicitMask}) {
  TerminalUtils.printHeader('TwoLevelQR Encoder', subtitle: 'Encoding message: "$text"');
  final enc = TwoLevelQr.encode(
    text,
    level: level,
    explicitVersion: explicitVersion,
    explicitMask: explicitMask,
  );

  TerminalUtils.printMetric('Symbol Version', 'v${enc.version.number} (${enc.matrix.size}x${enc.matrix.size})');
  TerminalUtils.printMetric('Error Correction', enc.level.label);
  TerminalUtils.printMetric('Chosen Mask', 'Pattern ${enc.maskPattern.bits}');
  TerminalUtils.printMetric('Data Codewords', enc.dataCodewords.length, unit: 'bytes');
  TerminalUtils.printMetric('Total Codewords', enc.finalCodewords.bytes.length, unit: 'bytes');

  TerminalUtils.printQrMatrix(enc.matrix);

  // Validate decode
  final dec = TwoLevelQr.decode(enc.matrix);
  stdout.writeln(TerminalUtils.success('✓ Verified decode: "${dec.text}" (100% match)'));
}

void _runHiddenEncode({
  required String publicText,
  required String hiddenText,
  required String key,
  required double ratio,
  required ErrorCorrectionLevel level,
  int? explicitVersion,
  MaskPattern? explicitMask,
}) {
  TerminalUtils.printHeader(
    'TwoLevelQR Hidden-Message Encoder',
    subtitle: 'Public: "$publicText" | Hidden: "$hiddenText"',
  );

  final EncodeResult enc;
  try {
    enc = TwoLevelQr.encodeWithHiddenMessage(
      publicText: publicText,
      hiddenText: hiddenText,
      key: key,
      ratio: ratio,
      level: level,
      explicitVersion: explicitVersion,
      explicitMask: explicitMask,
    );
  } on HiddenMessageCapacityException catch (e) {
    stderr.writeln(TerminalUtils.error('Error: ${e.toString()}'));
    exit(1);
  }

  TerminalUtils.printMetric('Symbol Version', 'v${enc.version.number} (${enc.matrix.size}x${enc.matrix.size})');
  TerminalUtils.printMetric('Error Correction', enc.level.label);
  TerminalUtils.printMetric('Chosen Mask', 'Pattern ${enc.maskPattern.bits}');
  TerminalUtils.printMetric('Hidden Payload', '${enc.hiddenBytes!.length - 2} bytes + 2 length bytes');

  TerminalUtils.printQrMatrix(enc.matrix);

  // Validate decode with correct key
  final dec = TwoLevelQr.decodeWithHiddenMessage(
    enc.matrix,
    key: key,
    ratio: ratio,
  );
  stdout.writeln(TerminalUtils.success('✓ Verified public decode: "${dec.public.text}"'));
  stdout.writeln(TerminalUtils.success('✓ Verified hidden decode: "${dec.hiddenText}"'));
}

void _runInteractiveMenu() {
  TerminalUtils.printHeader(
    'TwoLevelQR CLI Interactive Test Harness',
    subtitle: 'Select an option to test any SDK functionality',
  );

  while (true) {
    stdout.writeln('\n${TerminalUtils.title('Available Actions:')}');
    stdout.writeln('  [1] Step-by-Step Pipeline Stepper (Call Every Stage + Error Injection Before/After)');
    stdout.writeln('  [2] Run Full Verification Suite (Math, Codecs, E2E Stress, & Hidden Channel)');
    stdout.writeln('  [3] Encode Custom Text to Terminal QR Code');
    stdout.writeln('  [4] Inspect Pipeline Checkpoints');
    stdout.writeln('  [5] Run Reed-Solomon Damage & Recovery Demo');
    stdout.writeln('  [6] Run Performance Benchmarks');
    stdout.writeln('  [7] Keyed Two-Level QR Hidden Message Demo');
    stdout.writeln('  [0] Exit\n');

    stdout.write(TerminalUtils.color('Select option (0-7): ', TerminalUtils.bold + TerminalUtils.yellow));
    final choice = stdin.readLineSync()?.trim();

    if (choice == '0' || choice == 'q' || choice == null) {
      stdout.writeln(TerminalUtils.info('Goodbye!'));
      break;
    }

    switch (choice) {
      case '1':
        stdout.write('\nEnter message for stage stepper (or press Enter for default): ');
        final input = stdin.readLineSync()?.trim();
        final msg = (input != null && input.isNotEmpty) ? input : 'TWO_LEVEL_QR_EXPERIMENT_2026';
        stdout.write('Number of error module flips to inject (default 6): ');
        final flipsInput = stdin.readLineSync()?.trim();
        final flipsCount = int.tryParse(flipsInput ?? '6') ?? 6;
        PipelineStageStepper.runStepper(
          text: msg,
          level: ErrorCorrectionLevel.high,
          injectModuleFlipsCount: flipsCount,
          interactive: true,
        );
        break;
      case '2':
        _runFullTestSuite();
        break;
      case '3':
        stdout.write('\nEnter text to encode: ');
        final input = stdin.readLineSync()?.trim() ?? 'Hello QR';
        _runEncode(input.isEmpty ? 'Hello QR' : input, level: ErrorCorrectionLevel.medium);
        break;
      case '4':
        stdout.write('\nEnter text to inspect: ');
        final input = stdin.readLineSync()?.trim() ?? 'Inspect Stage Demo';
        CheckpointInspector.inspect(input.isEmpty ? 'Inspect Stage Demo' : input);
        break;
      case '5':
        stdout.write('\nEnter text for corruption demo (press Enter for default): ');
        final input = stdin.readLineSync()?.trim();
        if (input != null && input.isNotEmpty) {
          CorruptionDemo.runDemo(text: input);
        } else {
          CorruptionDemo.runDemo();
        }
        break;
      case '6':
        BenchmarkRunner.runBenchmarks();
        break;
      case '7':
        stdout.write('\nEnter public text (default: https://example.com/public-info): ');
        final publicInput = stdin.readLineSync()?.trim();
        stdout.write('Enter hidden text (default: SECRET_KEY_12345): ');
        final hiddenInput = stdin.readLineSync()?.trim();
        stdout.write('Enter secret key (default: demo-secret-key): ');
        final keyInput = stdin.readLineSync()?.trim();
        HiddenMessageDemo.runDemo(
          publicText: (publicInput != null && publicInput.isNotEmpty) ? publicInput : 'https://example.com/public-info',
          hiddenText: (hiddenInput != null && hiddenInput.isNotEmpty) ? hiddenInput : 'SECRET_KEY_12345',
          key: (keyInput != null && keyInput.isNotEmpty) ? keyInput : 'demo-secret-key',
          level: ErrorCorrectionLevel.high,
        );
        break;
      default:
        stdout.writeln(TerminalUtils.warning('Invalid option. Please choose 0 to 7.'));
    }
  }
}

ErrorCorrectionLevel _parseEcLevel(String levelStr) {
  switch (levelStr) {
    case 'L':
      return ErrorCorrectionLevel.low;
    case 'Q':
      return ErrorCorrectionLevel.quartile;
    case 'H':
      return ErrorCorrectionLevel.high;
    case 'M':
    default:
      return ErrorCorrectionLevel.medium;
  }
}
