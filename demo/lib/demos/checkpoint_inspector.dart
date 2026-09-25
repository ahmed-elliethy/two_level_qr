import 'dart:io';
import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// Interactive inspector demonstrating all first-class pipeline checkpoints of TwoLevelQR.
class CheckpointInspector {
  CheckpointInspector._();

  static void inspect(String text, {ErrorCorrectionLevel level = ErrorCorrectionLevel.medium}) {
    TerminalUtils.printHeader(
      'TwoLevelQR Checkpoint Inspector',
      subtitle: 'Inspecting all first-class stages for: "$text"',
    );

    final enc = TwoLevelQr.encode(text, level: level);

    // ---- Stage 1: Text & Segmentation ----
    TerminalUtils.printSection('Stage 1: Text & Mode Segmentation');
    TerminalUtils.printMetric('Input Message', '"${enc.text}"');
    TerminalUtils.printMetric('Character Length', enc.text.length, unit: 'characters');
    for (var i = 0; i < enc.segments.length; i++) {
      final s = enc.segments[i];
      stdout.writeln('    • Segment #$i: Mode=${TerminalUtils.info(s.mode.name)}, Count=${s.characterCount}');
    }

    // ---- Stage 2: Data Codewords ----
    TerminalUtils.printSection('Stage 2: Data Codewords');
    TerminalUtils.printMetric('Symbol Version', 'v${enc.version.number} (${enc.version.size}x${enc.version.size} modules)');
    TerminalUtils.printMetric('Target EC Level', '${enc.level.label} (~${_ecPercentage(enc.level)}% recovery)');
    TerminalUtils.printMetric('Data Codewords Count', enc.dataCodewords.length, unit: 'bytes');
    final hexDump = enc.dataCodewords.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    stdout.writeln('    Hex: ${TerminalUtils.color(hexDump, TerminalUtils.cyan)}');

    // ---- Stage 3: Reed-Solomon Blocks ----
    TerminalUtils.printSection('Stage 3: Reed-Solomon Blocks & ECC Generation');
    TerminalUtils.printMetric('Total RS Blocks', enc.rsBlocks.length);
    for (final b in enc.rsBlocks) {
      stdout.writeln(
        '    • Block #${b.blockIndex}: Data=${b.dataCodewords.length} bytes, ECC=${b.eccCodewords.length} bytes (Total=${b.totalCodewords} bytes)',
      );
    }

    // ---- Stage 4: Interleaved Final Codewords ----
    TerminalUtils.printSection('Stage 4: Interleaved Codewords & Remainder Bits');
    TerminalUtils.printMetric('Interleaved Stream', enc.finalCodewords.bytes.length, unit: 'bytes');
    TerminalUtils.printMetric('Remainder Bits', enc.finalCodewords.remainderBitsCount, unit: 'bits');
    TerminalUtils.printMetric('Total Bitstream Length', enc.finalCodewords.bitBuffer.length, unit: 'bits');

    // ---- Stage 5: Mask Pattern Evaluation ----
    TerminalUtils.printSection('Stage 5: Mask Pattern Optimization');
    TerminalUtils.printMetric('Chosen Mask', 'Pattern ${enc.maskPattern.bits} (${enc.maskPattern.name})');

    // ---- Stage 6: Final Matrix ----
    TerminalUtils.printSection('Stage 6: Rendered QR Matrix');
    TerminalUtils.printMetric('Matrix Side Length', enc.matrix.size, unit: 'modules');
    TerminalUtils.printMetric('Total Dark Modules', enc.matrix.countDark());
    TerminalUtils.printMetric('Dark Module Ratio', '${((enc.matrix.countDark() * 100) / (enc.matrix.size * enc.matrix.size)).toStringAsFixed(1)}%');

    TerminalUtils.printQrMatrix(enc.matrix);
  }

  static String _ecPercentage(ErrorCorrectionLevel level) {
    switch (level) {
      case ErrorCorrectionLevel.low:
        return '7';
      case ErrorCorrectionLevel.medium:
        return '15';
      case ErrorCorrectionLevel.quartile:
        return '25';
      case ErrorCorrectionLevel.high:
        return '30';
    }
  }
}
