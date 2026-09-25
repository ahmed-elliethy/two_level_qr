import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// CLI test suite for the keyed two-level QR hidden-message channel.
class HiddenMessageTests {
  HiddenMessageTests._();

  static int runAll() {
    TerminalUtils.printSection('Suite 3: Keyed Two-Level QR Hidden Message Channel');
    var failures = 0;

    failures += _testRoundtrip();
    failures += _testWrongKeyReturnsGarbage();
    failures += _testStandardDecodeCompatibility();
    failures += _testDifferentKeysProduceDifferentMatrices();
    failures += _testLongerUtf8Secret();
    failures += _testNoisePlusHiddenErrors();
    failures += _testCapacityOverflow();
    failures += _testRatioMismatch();

    return failures;
  }

  static int _testRoundtrip() {
    const public = 'https://example.com/public-info';
    const hidden = 'SECRET_42';
    const key = 'my-secret-key';

    try {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );
      final dec = TwoLevelQr.decodeWithHiddenMessage(enc.matrix, key: key);

      final pass = dec.public.text == public && dec.hiddenText == hidden;
      TerminalUtils.printTestResult(
        'Hidden Roundtrip (correct key)',
        pass,
        extra: 'v${enc.version.number}-${enc.level.label}',
      );
      return pass ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult('Hidden Roundtrip (correct key)', false, extra: e.toString());
      return 1;
    }
  }

  static int _testWrongKeyReturnsGarbage() {
    const public = 'https://example.com/public-info';
    const hidden = 'SECRET_42';
    const key = 'correct-key';

    try {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );
      final dec = TwoLevelQr.decodeWithHiddenMessage(enc.matrix, key: 'wrong-key');

      final pass = dec.public.text == public && dec.hiddenText != hidden;
      TerminalUtils.printTestResult(
        'Wrong Key Returns Garbage',
        pass,
        extra: 'hidden="${dec.hiddenText}"',
      );
      return pass ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult('Wrong Key Returns Garbage', false, extra: e.toString());
      return 1;
    }
  }

  static int _testStandardDecodeCompatibility() {
    const public = 'https://example.com/public-info';
    const hidden = 'SECRET_42';
    const key = 'my-secret-key';

    try {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );
      final dec = TwoLevelQr.decode(enc.matrix);

      final pass = dec.text == public && dec.errorsCorrected > 0;
      TerminalUtils.printTestResult(
        'Standard Decode Still Recovers Public Text',
        pass,
        extra: '${dec.errorsCorrected} error(s) corrected',
      );
      return pass ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult('Standard Decode Still Recovers Public Text', false, extra: e.toString());
      return 1;
    }
  }

  static int _testDifferentKeysProduceDifferentMatrices() {
    const public = 'https://example.com/public-info';
    const hidden = 'SECRET_42';

    try {
      final enc1 = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: 'key-alpha',
        level: ErrorCorrectionLevel.high,
      );
      final enc2 = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: 'key-beta',
        level: ErrorCorrectionLevel.high,
      );

      final pass = enc1.matrix != enc2.matrix;
      TerminalUtils.printTestResult(
        'Different Keys Produce Different Matrices',
        pass,
      );
      return pass ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult('Different Keys Produce Different Matrices', false, extra: e.toString());
      return 1;
    }
  }

  static int _testLongerUtf8Secret() {
    const public = 'https://example.com/two-level-qr';
    const hidden = 'The quick brown fox jumps over 13 lazy dogs. 🦊🐕';
    const key = 'utf8-key-123';

    try {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
        explicitVersion: 10,
      );
      final dec = TwoLevelQr.decodeWithHiddenMessage(enc.matrix, key: key);

      final pass = dec.public.text == public && dec.hiddenText == hidden;
      TerminalUtils.printTestResult(
        'Longer UTF-8 Secret (v10-H)',
        pass,
        extra: '${hidden.length} chars / ${hidden.runes.length} runes',
      );
      return pass ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult('Longer UTF-8 Secret (v10-H)', false, extra: e.toString());
      return 1;
    }
  }

  static int _testNoisePlusHiddenErrors() {
    const public = 'https://example.com/public-info';
    const hidden = 'SECRET_42';
    const key = 'noise-key';

    try {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );

      final noisy = enc.matrix.clone();
      noisy.toggle(10, 10);
      noisy.toggle(12, 14);
      noisy.toggle(14, 18);

      final dec = TwoLevelQr.decodeWithHiddenMessage(noisy, key: key);

      final pass = dec.public.text == public && dec.hiddenText == hidden;
      TerminalUtils.printTestResult(
        'Scanner Noise + Hidden Errors Corrected',
        pass,
        extra: '${dec.public.errorsCorrected} error(s) corrected',
      );
      return pass ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult('Scanner Noise + Hidden Errors Corrected', false, extra: e.toString());
      return 1;
    }
  }

  static int _testCapacityOverflow() {
    var fails = 0;
    const public = 'https://example.com';
    const key = 'capacity-key';

    // 1. Fixed version overflow should still throw ArgumentError.
    try {
      TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: 'A' * 100,
        key: key,
        level: ErrorCorrectionLevel.high,
        explicitVersion: 1,
      );
      TerminalUtils.printTestResult('Fixed Version Capacity Overflow Throws', false, extra: 'no exception');
      fails++;
    } on ArgumentError catch (_) {
      TerminalUtils.printTestResult('Fixed Version Capacity Overflow Throws', true);
    } catch (e) {
      TerminalUtils.printTestResult('Fixed Version Capacity Overflow Throws', false, extra: 'wrong exception: $e');
      fails++;
    }

    // 2. Max-version overflow should throw a meaningful HiddenMessageCapacityException.
    try {
      TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: 'A' * 2000,
        key: key,
        level: ErrorCorrectionLevel.high,
      );
      TerminalUtils.printTestResult('Max-Version Capacity Error is Meaningful', false, extra: 'no exception');
      fails++;
    } on HiddenMessageCapacityException catch (e) {
      final pass = e.hiddenPayloadBytes == 2000 &&
          e.totalHiddenBytes == 2002 &&
          e.maxCapacityBytes > 0 &&
          e.maxCapacityBytes < 2002;
      TerminalUtils.printTestResult(
        'Max-Version Capacity Error is Meaningful',
        pass,
        extra: 'maxCapacity=${e.maxCapacityBytes}',
      );
      if (!pass) fails++;
    } catch (e) {
      TerminalUtils.printTestResult('Max-Version Capacity Error is Meaningful', false, extra: 'wrong exception: $e');
      fails++;
    }

    return fails;
  }

  static int _testRatioMismatch() {
    const public = 'https://example.com/public-info';
    const hidden = 'SECRET_42';
    const key = 'ratio-key';

    try {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        ratio: 0.8,
        level: ErrorCorrectionLevel.high,
      );
      final decCorrect = TwoLevelQr.decodeWithHiddenMessage(enc.matrix, key: key, ratio: 0.8);
      final decWrong = TwoLevelQr.decodeWithHiddenMessage(enc.matrix, key: key, ratio: 0.5);

      final pass = decCorrect.hiddenText == hidden && decWrong.hiddenText != hidden;
      TerminalUtils.printTestResult(
        'Ratio Mismatch Produces Garbage',
        pass,
        extra: 'correct="${decCorrect.hiddenText}", wrong="${decWrong.hiddenText}"',
      );
      return pass ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult('Ratio Mismatch Produces Garbage', false, extra: e.toString());
      return 1;
    }
  }
}
