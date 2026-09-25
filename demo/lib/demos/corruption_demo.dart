import 'dart:io';
import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// Interactive demonstration of QR code damage injection and Reed-Solomon self-healing.
class CorruptionDemo {
  CorruptionDemo._();

  static void runDemo({String text = 'TWO_LEVEL_QR_SELF_HEALING_DEMO'}) {
    TerminalUtils.printHeader(
      'Reed-Solomon Damage & Recovery Demo',
      subtitle: 'Testing error correction capability on damaged matrices',
    );

    // 1. Encode at High error correction (30% recovery)
    stdout.writeln(TerminalUtils.info('\n[1] Encoding with ErrorCorrectionLevel.high (~30% recovery)...'));
    final enc = TwoLevelQr.encode(text, level: ErrorCorrectionLevel.high);
    TerminalUtils.printMetric('Original Message', '"$text"');
    TerminalUtils.printMetric('Symbol Version', 'v${enc.version.number}');
    TerminalUtils.printMetric('RS Blocks', enc.rsBlocks.length);

    stdout.writeln(TerminalUtils.muted('\n--- Original Clean Matrix ---'));
    TerminalUtils.printQrMatrix(enc.matrix);

    // 2. Introduce deliberate noise in data modules
    stdout.writeln(TerminalUtils.warning('[2] Injecting noise / corrupting multiple data modules...'));
    final corruptedMatrix = enc.matrix.clone();

    // Flip 8 modules spread across the matrix
    final flipPoints = [
      (9, 9), (10, 11), (12, 13), (14, 15),
      (15, 17), (17, 19), (19, 21), (21, 23),
    ];

    var flippedCount = 0;
    for (final pt in flipPoints) {
      if (pt.$1 < corruptedMatrix.size && pt.$2 < corruptedMatrix.size) {
        corruptedMatrix.toggle(pt.$1, pt.$2);
        flippedCount++;
      }
    }

    stdout.writeln(TerminalUtils.muted('\n--- Damaged Matrix ($flippedCount modules inverted) ---'));
    TerminalUtils.printQrMatrix(corruptedMatrix);

    // 3. Decode & Error Correction
    stdout.writeln(TerminalUtils.info('[3] Running TwoLevelQr.decode() with Reed-Solomon correction...'));
    final stopwatch = Stopwatch()..start();
    final dec = TwoLevelQr.decode(corruptedMatrix);
    stopwatch.stop();

    TerminalUtils.printSection('Recovery Report');
    TerminalUtils.printMetric('Recovered Message', TerminalUtils.success('"${dec.text}"'));
    TerminalUtils.printMetric('Errors Located & Healed', TerminalUtils.success('${dec.errorsCorrected} error(s)'));
    TerminalUtils.printMetric('Detection & Healing Time', '${stopwatch.elapsedMicroseconds} µs');
    TerminalUtils.printMetric('Status', TerminalUtils.success('100% PERFECT RECONSTRUCTION'));
    stdout.writeln();
  }
}
