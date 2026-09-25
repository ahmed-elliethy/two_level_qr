import 'dart:io';
import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// Stage-by-Stage Pipeline Stepper and Error Injection Lab.
///
/// Demonstrates every single stage call in the ENCODE and DECODE pipelines:
/// ENCODE: text → segments → dataCodewords → RS ecc → interleave → finalCodewords → place+mask → matrix
/// DECODE: matrix → unmask → rawCodewords → deinterleave → RS decode → correctedCodewords → segments → text
class PipelineStageStepper {
  PipelineStageStepper._();

  /// Runs the full pipeline step-by-step with interactive or automated error injection.
  static void runStepper({
    String text = 'TWO_LEVEL_QR_PIPELINE_EXPERIMENT_2026',
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
    int? injectModuleFlipsCount = 6,
    List<int>? injectByteErrorsIndices,
    bool interactive = false,
  }) {
    TerminalUtils.printHeader(
      'TwoLevelQR Stage-by-Stage Pipeline Stepper',
      subtitle: 'Calling every stage individually & inspecting before/after error correction',
    );

    // =========================================================================
    // ENCODE PIPELINE
    // =========================================================================
    stdout.writeln(TerminalUtils.title('\n╔══════════════════════════════════════════════════════════════════════════╗'));
    stdout.writeln(TerminalUtils.title('║                        ENCODE PIPELINE STAGES                            ║'));
    stdout.writeln(TerminalUtils.title('╚══════════════════════════════════════════════════════════════════════════╝'));

    // ENCODE Stage 1: text → segments
    TerminalUtils.printSection('ENCODE Stage 1: text → segments');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage1SegmentText(text)...'));
    final segments = TwoLevelQr.stage1SegmentText(text);
    TerminalUtils.printMetric('Input Text', '"$text"');
    TerminalUtils.printMetric('Segments Count', segments.length);
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      stdout.writeln('    • Segment #$i: Mode=${TerminalUtils.info(s.mode.name)}, Count=${s.characterCount}');
    }
    _stepPrompt(interactive);

    // ENCODE Stage 2: segments → dataCodewords
    TerminalUtils.printSection('ENCODE Stage 2: segments → dataCodewords');
    final version = QrVersion.findMinimumVersion(
      requiredDataBytes: text.length + 4,
      level: level,
    );
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage2EncodeDataCodewords(segments, v${version.number}, ${level.label})...'));
    final dataCodewords = TwoLevelQr.stage2EncodeDataCodewords(
      segments: segments,
      version: version,
      level: level,
    );
    TerminalUtils.printMetric('Symbol Version', 'v${version.number} (${version.size}x${version.size})');
    TerminalUtils.printMetric('Data Codewords', dataCodewords.length, unit: 'bytes');
    stdout.writeln('    Data Hex: ${TerminalUtils.color(_hex(dataCodewords.bytes), TerminalUtils.cyan)}');
    _stepPrompt(interactive);

    // ENCODE Stage 3: dataCodewords → RS ecc (Blocks)
    TerminalUtils.printSection('ENCODE Stage 3: dataCodewords → RS ecc');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage3GenerateRsBlocks(dataCodewords)...'));
    final rsBlocks = TwoLevelQr.stage3GenerateRsBlocks(
      dataCodewords: dataCodewords,
      version: version,
      level: level,
    );
    TerminalUtils.printMetric('RS Blocks Generated', rsBlocks.length);
    for (final b in rsBlocks) {
      stdout.writeln('    • Block #${b.blockIndex}: Data=${b.dataCodewords.length}B, ECC=${b.eccCodewords.length}B');
      stdout.writeln('      Data: ${TerminalUtils.muted(_hex(b.dataCodewords))}');
      stdout.writeln('      ECC:  ${TerminalUtils.color(_hex(b.eccCodewords), TerminalUtils.yellow)}');
    }
    _stepPrompt(interactive);

    // ENCODE Stage 4: RS blocks → interleave → finalCodewords
    TerminalUtils.printSection('ENCODE Stage 4: RS blocks → interleave → finalCodewords');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage4InterleaveBlocks(dataCodewords)...'));
    final finalCodewords = TwoLevelQr.stage4InterleaveBlocks(
      dataCodewords: dataCodewords,
      version: version,
      level: level,
    );
    TerminalUtils.printMetric('Final Interleaved Stream', finalCodewords.bytes.length, unit: 'bytes');
    TerminalUtils.printMetric('Remainder Bits', finalCodewords.remainderBitsCount, unit: 'bits');
    stdout.writeln('    Interleaved Hex: ${TerminalUtils.color(_hex(finalCodewords.bytes), TerminalUtils.cyan)}');
    _stepPrompt(interactive);

    // ENCODE Stage 5: finalCodewords → place+mask → matrix
    TerminalUtils.printSection('ENCODE Stage 5: finalCodewords → place+mask → matrix');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage5PlaceAndMaskMatrix(finalCodewords)...'));
    final stage5Result = TwoLevelQr.stage5PlaceAndMaskMatrix(
      finalCodewords: finalCodewords,
      version: version,
      level: level,
    );
    final cleanMatrix = stage5Result.matrix;
    TerminalUtils.printMetric('Matrix Size', '${cleanMatrix.size}x${cleanMatrix.size}');
    TerminalUtils.printMetric('Applied Mask', 'Pattern ${stage5Result.maskPattern.bits} (${stage5Result.maskPattern.name})');
    TerminalUtils.printMetric('Format Info Bits', '0x${stage5Result.formatInfo.bits15.toRadixString(16).padLeft(4, '0')}');

    stdout.writeln(TerminalUtils.muted('\n--- Clean Encoded QR Matrix ---'));
    TerminalUtils.printQrMatrix(cleanMatrix);
    _stepPrompt(interactive);

    // =========================================================================
    // ERROR INJECTION
    // =========================================================================
    stdout.writeln(TerminalUtils.title('\n╔══════════════════════════════════════════════════════════════════════════╗'));
    stdout.writeln(TerminalUtils.title('║                     ERROR INJECTION EXPERIMENT                           ║'));
    stdout.writeln(TerminalUtils.title('╚══════════════════════════════════════════════════════════════════════════╝'));

    final damagedMatrix = cleanMatrix.clone();
    final corruptedModuleCoords = <(int, int)>[];

    if (injectModuleFlipsCount != null && injectModuleFlipsCount > 0) {
      stdout.writeln(TerminalUtils.warning('Injecting $injectModuleFlipsCount bit errors directly into matrix modules...'));
      final sampleCoords = [
        (9, 9), (10, 11), (12, 13), (14, 15), (16, 17), (18, 19),
        (20, 21), (22, 23), (11, 25), (13, 27)
      ];

      for (var i = 0; i < injectModuleFlipsCount && i < sampleCoords.length; i++) {
        final coord = sampleCoords[i];
        if (coord.$1 < damagedMatrix.size && coord.$2 < damagedMatrix.size) {
          damagedMatrix.toggle(coord.$1, coord.$2);
          corruptedModuleCoords.add(coord);
        }
      }

      stdout.writeln('    Flipped modules at: ${corruptedModuleCoords.map((c) => "(${c.$1},${c.$2})").join(", ")}');
      stdout.writeln(TerminalUtils.muted('\n--- Damaged QR Matrix ---'));
      TerminalUtils.printQrMatrix(damagedMatrix);
    }
    _stepPrompt(interactive);

    // =========================================================================
    // DECODE PIPELINE
    // =========================================================================
    stdout.writeln(TerminalUtils.title('\n╔══════════════════════════════════════════════════════════════════════════╗'));
    stdout.writeln(TerminalUtils.title('║                        DECODE PIPELINE STAGES                            ║'));
    stdout.writeln(TerminalUtils.title('╚══════════════════════════════════════════════════════════════════════════╝'));

    // DECODE Stage 1: matrix → unmask
    TerminalUtils.printSection('DECODE Stage 1: matrix → unmask');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage1UnmaskMatrix(damagedMatrix)...'));
    final unmaskResult = TwoLevelQr.stage1UnmaskMatrix(damagedMatrix);
    TerminalUtils.printMetric('Detected Version', 'v${unmaskResult.version.number}');
    TerminalUtils.printMetric('Detected EC Level', unmaskResult.formatInfo.level.label);
    TerminalUtils.printMetric('Detected Mask', 'Pattern ${unmaskResult.formatInfo.maskPattern.bits}');
    _stepPrompt(interactive);

    // DECODE Stage 2: unmasked matrix → rawCodewords (WITH errors)
    TerminalUtils.printSection('DECODE Stage 2: unmasked matrix → rawCodewords (WITH errors)');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage2ExtractRawCodewords(unmaskedMatrix)...'));
    var rawCodewords = TwoLevelQr.stage2ExtractRawCodewords(
      unmaskedMatrix: unmaskResult.unmaskedMatrix,
      version: unmaskResult.version,
      level: unmaskResult.formatInfo.level,
    );

    // Optional direct byte injection if requested
    if (injectByteErrorsIndices != null && injectByteErrorsIndices.isNotEmpty) {
      final corruptedBytes = List<int>.from(rawCodewords.bytes);
      for (final idx in injectByteErrorsIndices) {
        if (idx < corruptedBytes.length) {
          corruptedBytes[idx] ^= 0xAA;
        }
      }
      rawCodewords = RawCodewords(
        bytes: corruptedBytes,
        version: unmaskResult.version,
        level: unmaskResult.formatInfo.level,
      );
      stdout.writeln(TerminalUtils.warning('Injected byte flips at indices: $injectByteErrorsIndices'));
    }

    TerminalUtils.printMetric('Extracted Raw Codewords', rawCodewords.length, unit: 'bytes');
    _printCodewordsDiff(finalCodewords.bytes, rawCodewords.bytes, label: 'Raw Codewords vs Original Final');
    _stepPrompt(interactive);

    // DECODE Stage 3: rawCodewords → deinterleave
    TerminalUtils.printSection('DECODE Stage 3: rawCodewords → deinterleave (Raw RS Blocks)');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage3DeinterleaveRawCodewords(rawCodewords)...'));
    final rawBlocks = TwoLevelQr.stage3DeinterleaveRawCodewords(
      rawCodewords: rawCodewords,
      version: unmaskResult.version,
      level: unmaskResult.formatInfo.level,
    );
    TerminalUtils.printMetric('Deinterleaved RS Blocks', rawBlocks.length);
    for (var i = 0; i < rawBlocks.length; i++) {
      final rawB = rawBlocks[i];
      final origB = rsBlocks[i];
      final diffs = _findByteDiffs(origB.fullBlock, rawB.fullBlock);
      final status = diffs.isEmpty
          ? TerminalUtils.success('Clean (0 errors)')
          : TerminalUtils.error('Corrupted (${diffs.length} byte error(s) at offsets: $diffs)');
      stdout.writeln('    • Block #$i: $status');
    }
    _stepPrompt(interactive);

    // DECODE Stage 4: raw RS blocks → RS decode → correctedCodewords
    TerminalUtils.printSection('DECODE Stage 4: raw RS blocks → RS decode → correctedCodewords');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage4CorrectRsBlocks(rawBlocks)...'));

    final sw = Stopwatch()..start();
    final correctedCodewords = TwoLevelQr.stage4CorrectRsBlocks(
      rawBlocks: rawBlocks,
      version: unmaskResult.version,
      level: unmaskResult.formatInfo.level,
    );
    sw.stop();

    TerminalUtils.printMetric('RS Correction Time', '${sw.elapsedMicroseconds} µs');
    TerminalUtils.printMetric('Total Errors Located & Corrected', TerminalUtils.success('${correctedCodewords.errorsCorrected} error(s)'));

    // Side-by-Side Comparison of RS Blocks Before vs After Correction
    stdout.writeln('\n${TerminalUtils.title('    === RS Blocks: BEFORE vs AFTER Error Correction ===')}');
    for (var i = 0; i < rawBlocks.length; i++) {
      final rawB = rawBlocks[i];
      final corrB = correctedCodewords.blocks[i];
      final origB = rsBlocks[i];

      stdout.writeln('\n    [ Block #$i ]');
      stdout.writeln('      ${TerminalUtils.error('BEFORE (Raw):     ')} ${_highlightDiffs(rawB.dataCodewords, origB.dataCodewords, isError: true)}');
      stdout.writeln('      ${TerminalUtils.success('AFTER (Corrected):')} ${_highlightDiffs(corrB.dataCodewords, rawB.dataCodewords, isError: false)}');
    }
    _stepPrompt(interactive);

    // DECODE Stage 5: correctedCodewords → segments
    TerminalUtils.printSection('DECODE Stage 5: correctedCodewords → segments');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage5DecodeSegments(dataCodewords)...'));
    final decodedSegments = TwoLevelQr.stage5DecodeSegments(
      dataCodewords: correctedCodewords.dataCodewords,
      version: unmaskResult.version,
    );
    TerminalUtils.printMetric('Decoded Segments Count', decodedSegments.length);
    for (var i = 0; i < decodedSegments.length; i++) {
      final s = decodedSegments[i];
      stdout.writeln('    • Decoded Segment #$i: Mode=${TerminalUtils.info(s.mode.name)}, Count=${s.characterCount}');
    }
    _stepPrompt(interactive);

    // DECODE Stage 6: segments → text
    TerminalUtils.printSection('DECODE Stage 6: segments → text');
    stdout.writeln(TerminalUtils.info('Calling TwoLevelQr.stage6SegmentsToText(decodedSegments)...'));
    final decodedText = TwoLevelQr.stage6SegmentsToText(decodedSegments);

    TerminalUtils.printMetric('Original Text', '"$text"');
    TerminalUtils.printMetric('Decoded Text', TerminalUtils.success('"$decodedText"'));
    final match = decodedText == text;
    TerminalUtils.printMetric('Integrity Match', match ? TerminalUtils.success('100% PERFECT MATCH') : TerminalUtils.error('MISMATCH'));

    stdout.writeln(TerminalUtils.success('\n🎉 Pipeline Stage-by-Stage Verification Complete!\n'));
  }

  static void _stepPrompt(bool interactive) {
    if (!interactive) return;
    stdout.write(TerminalUtils.muted('\n[Press Enter to proceed to next stage...] '));
    stdin.readLineSync();
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  static List<int> _findByteDiffs(List<int> orig, List<int> raw) {
    final diffs = <int>[];
    final minLen = orig.length < raw.length ? orig.length : raw.length;
    for (var i = 0; i < minLen; i++) {
      if (orig[i] != raw[i]) diffs.add(i);
    }
    return diffs;
  }

  static String _highlightDiffs(List<int> target, List<int> compare, {required bool isError}) {
    final sb = StringBuffer();
    final minLen = target.length < compare.length ? target.length : compare.length;
    for (var i = 0; i < minLen; i++) {
      final h = target[i].toRadixString(16).padLeft(2, '0').toUpperCase();
      if (target[i] != compare[i]) {
        sb.write(isError ? TerminalUtils.color(h, TerminalUtils.bold + TerminalUtils.red) : TerminalUtils.color(h, TerminalUtils.bold + TerminalUtils.green));
      } else {
        sb.write(TerminalUtils.muted(h));
      }
      sb.write(' ');
    }
    return sb.toString().trim();
  }

  static void _printCodewordsDiff(List<int> original, List<int> raw, {required String label}) {
    final diffs = _findByteDiffs(original, raw);
    if (diffs.isEmpty) {
      stdout.writeln('    $label: ${TerminalUtils.success("0 byte differences")}');
    } else {
      stdout.writeln('    $label: ${TerminalUtils.error("${diffs.length} byte difference(s) at positions: $diffs")}');
    }
  }
}
