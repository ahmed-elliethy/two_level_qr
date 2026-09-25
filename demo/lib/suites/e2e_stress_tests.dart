import 'dart:math';
import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// End-to-end stress testing across multiple payloads, versions, and EC levels.
class E2eStressTests {
  E2eStressTests._();

  static int runAll() {
    TerminalUtils.printSection('Suite 2: End-to-End Stress & Roundtrip Tests');
    var failures = 0;

    // 1. Standard Payload Roundtrips
    failures += _testStandardPayloads();

    // 2. Randomized Stress Test (50 payloads)
    failures += _testRandomizedStress(count: 50);

    // 3. Error Tolerance & Noise Injections
    failures += _testNoiseInjections();

    return failures;
  }

  static int _testStandardPayloads() {
    var fails = 0;
    final testCases = <({String name, String text, ErrorCorrectionLevel level})>[
      (name: 'Short Numeric (v1-L)', text: '1234567890', level: ErrorCorrectionLevel.low),
      (name: 'Alphanumeric URL (v1-M)', text: 'HTTPS://EXAMPLE.COM', level: ErrorCorrectionLevel.medium),
      (name: 'Mixed UTF-8 / JSON (v2-Q)', text: '{"status":"ok","code":200}', level: ErrorCorrectionLevel.quartile),
      (name: 'Multilingual & Emojis (v3-H)', text: 'TwoLevelQR ⚡ 🚀 clean architecture!', level: ErrorCorrectionLevel.high),
      (name: 'Long Document URL (v7-M)', text: 'https://github.com/example/two_level_qr/blob/master/README.md?ref=release-v1.0.0-final', level: ErrorCorrectionLevel.medium),
    ];

    for (final tc in testCases) {
      try {
        final enc = TwoLevelQr.encode(tc.text, level: tc.level);
        final dec = TwoLevelQr.decode(enc.matrix);
        final pass = dec.text == tc.text && dec.level == tc.level;
        TerminalUtils.printTestResult(tc.name, pass, extra: 'v${enc.version.number}-${enc.level.label}, size ${enc.matrix.size}x${enc.matrix.size}');
        if (!pass) fails++;
      } catch (e) {
        TerminalUtils.printTestResult(tc.name, false, extra: e.toString());
        fails++;
      }
    }

    return fails;
  }

  static int _testRandomizedStress({int count = 50}) {
    var fails = 0;
    final random = Random(42);
    final levels = ErrorCorrectionLevel.values;
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.:/@';

    var passed = 0;
    for (var i = 0; i < count; i++) {
      final len = random.nextInt(60) + 5;
      final text = List.generate(len, (_) => chars[random.nextInt(chars.length)]).join();
      final level = levels[random.nextInt(levels.length)];

      try {
        final enc = TwoLevelQr.encode(text, level: level);
        final dec = TwoLevelQr.decode(enc.matrix);
        if (dec.text == text && dec.level == level) {
          passed++;
        } else {
          fails++;
        }
      } catch (_) {
        fails++;
      }
    }

    final allPass = fails == 0;
    TerminalUtils.printTestResult('Randomized Payload Stress ($passed/$count roundtrips passed)', allPass);
    return fails;
  }

  static int _testNoiseInjections() {
    var fails = 0;
    const text = 'SELF_HEALING_TWO_LEVEL_QR_CODE';
    final enc = TwoLevelQr.encode(text, level: ErrorCorrectionLevel.high);

    // Corrupt 6 modules in data regions
    final noisy = enc.matrix.clone();
    noisy.toggle(9, 9);
    noisy.toggle(10, 11);
    noisy.toggle(12, 13);
    noisy.toggle(14, 15);
    noisy.toggle(15, 17);
    noisy.toggle(16, 19);

    final dec = TwoLevelQr.decode(noisy);
    final healed = dec.text == text && dec.errorsCorrected > 0;
    TerminalUtils.printTestResult('Self-Healing: Reed-Solomon Multi-Module Recovery', healed, extra: '${dec.errorsCorrected} error(s) corrected');
    if (!healed) fails++;

    return fails;
  }
}
