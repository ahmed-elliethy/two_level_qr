import 'dart:io';
import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// Interactive demonstration of the keyed two-level QR hidden-message channel.
class HiddenMessageDemo {
  HiddenMessageDemo._();

  static void runDemo({
    String publicText = 'https://example.com/public-info',
    String hiddenText = 'SECRET_KEY_12345',
    String key = 'demo-secret-key',
    double ratio = 0.8,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
  }) {
    TerminalUtils.printHeader(
      'Keyed Two-Level QR Hidden Message Demo',
      subtitle: 'Public payload + secret payload embedded in RS error channel',
    );

    // 1. Encode public + hidden
    stdout.writeln(TerminalUtils.info('\n[1] Encoding two-level QR...'));
    final stopwatch = Stopwatch()..start();
    late final EncodeResult enc;
    try {
      enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: publicText,
        hiddenText: hiddenText,
        key: key,
        ratio: ratio,
        level: level,
      );
    } on HiddenMessageCapacityException catch (e) {
      stopwatch.stop();
      TerminalUtils.printSection('Capacity Error');
      stdout.writeln(TerminalUtils.error('  ${e.toString()}'));
      stdout.writeln();
      return;
    }
    stopwatch.stop();

    TerminalUtils.printMetric('Public Message', '"$publicText"');
    TerminalUtils.printMetric('Hidden Message', '"$hiddenText"');
    TerminalUtils.printMetric('Key', key);
    TerminalUtils.printMetric('Ratio', ratio);
    TerminalUtils.printMetric('Symbol Version', 'v${enc.version.number} (${enc.matrix.size}x${enc.matrix.size})');
    TerminalUtils.printMetric('Error Correction', enc.level.label);
    TerminalUtils.printMetric('Hidden Bytes Embedded', enc.hiddenBytes!.length - 2, unit: 'bytes payload + 2 length');
    TerminalUtils.printMetric('Encode Time', '${stopwatch.elapsedMicroseconds} µs');

    stdout.writeln(TerminalUtils.muted('\n--- Encoded Two-Level QR Matrix ---'));
    TerminalUtils.printQrMatrix(enc.matrix);

    // 2. Decode with correct key
    stdout.writeln(TerminalUtils.info('[2] Decoding with the CORRECT key...'));
    final decCorrect = TwoLevelQr.decodeWithHiddenMessage(
      enc.matrix,
      key: key,
      ratio: ratio,
    );

    TerminalUtils.printSection('Correct-Key Decode Report');
    TerminalUtils.printMetric('Recovered Public', TerminalUtils.success('"${decCorrect.public.text}"'));
    TerminalUtils.printMetric('Recovered Hidden', TerminalUtils.success('"${decCorrect.hiddenText}"'));
    TerminalUtils.printMetric('Errors Corrected', '${decCorrect.public.errorsCorrected} error(s)');

    // 3. Decode with wrong key
    stdout.writeln(TerminalUtils.warning('\n[3] Decoding with a WRONG key...'));
    final decWrong = TwoLevelQr.decodeWithHiddenMessage(
      enc.matrix,
      key: '$key-wrong',
      ratio: ratio,
    );

    TerminalUtils.printSection('Wrong-Key Decode Report');
    TerminalUtils.printMetric('Recovered Public', TerminalUtils.success('"${decWrong.public.text}"'));
    TerminalUtils.printMetric('Recovered Hidden', TerminalUtils.error('"${decWrong.hiddenText}"'));
    TerminalUtils.printMetric('Raw Garbage Bytes', decWrong.rawErrorBytes.length, unit: 'bytes');

    // 4. Standard decode (no hidden channel)
    stdout.writeln(TerminalUtils.info('\n[4] Running standard QR decode (any scanner)...'));
    final standard = TwoLevelQr.decode(enc.matrix);

    TerminalUtils.printSection('Standard Scanner Decode Report');
    TerminalUtils.printMetric('Recovered Public', TerminalUtils.success('"${standard.text}"'));
    TerminalUtils.printMetric('Errors Corrected', '${standard.errorsCorrected} error(s)');
    stdout.writeln(TerminalUtils.success('\n✓ Standard scanners only see the public payload.\n'));
  }
}
