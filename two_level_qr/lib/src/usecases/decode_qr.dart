import 'dart:convert';

import '../data/bit_stream_codec.dart';
import '../data/block_interleaver.dart';
import '../data/format_info_codec.dart';
import '../data/masking.dart';
import '../data/matrix_renderer.dart';
import '../data/reed_solomon.dart';
import '../data/version_info_codec.dart';
import '../decode_result.dart';
import '../domain/corrected_codewords.dart';
import '../domain/mode.dart';
import '../domain/ports.dart';
import '../domain/qr_matrix.dart';
import '../domain/rs_block.dart';
import '../domain/version.dart';

/// Clean-architecture use case implementing the complete QR Code decode pipeline.
class DecodeQr {
  DecodeQr({
    BitStreamCodecPort? bitStreamCodec,
    ReedSolomonCodecPort? rsCodec,
    BlockInterleaverPort? blockInterleaver,
    MaskingPort? masking,
    MatrixRendererPort? matrixRenderer,
    FormatInfoCodecPort? formatCodec,
    VersionInfoCodecPort? versionCodec,
  })  : bitStreamCodec = bitStreamCodec ?? const BitStreamCodec(),
        rsCodec = rsCodec ?? ReedSolomonCodec(),
        blockInterleaver = blockInterleaver ?? const BlockInterleaver(),
        masking = masking ?? const Masking(),
        matrixRenderer = matrixRenderer ?? const MatrixRenderer(),
        formatCodec = formatCodec ?? const FormatInfoCodec(),
        versionCodec = versionCodec ?? const VersionInfoCodec();

  final BitStreamCodecPort bitStreamCodec;
  final ReedSolomonCodecPort rsCodec;
  final BlockInterleaverPort blockInterleaver;
  final MaskingPort masking;
  final MatrixRendererPort matrixRenderer;
  final FormatInfoCodecPort formatCodec;
  final VersionInfoCodecPort versionCodec;

  /// Executes the complete QR decoding pipeline from [matrix].
  DecodeResult execute(QrMatrix matrix) {
    final size = matrix.size;
    if (size < 21 || (size - 17) % 4 != 0) {
      throw FormatException('Invalid QR matrix dimension: ${size}x$size');
    }

    // 1. Determine provisional version from matrix dimensions
    final vNum = (size - 17) ~/ 4;
    var version = QrVersion(vNum);

    // 2. Read Format Information
    final formatInfo = matrixRenderer.readFormatInfo(matrix);
    final level = formatInfo.level;
    final maskPattern = formatInfo.maskPattern;

    // 3. Read Version Information (if v >= 7)
    final versionInfo = matrixRenderer.readVersionInfo(matrix, size);
    if (versionInfo != null) {
      version = versionInfo.version;
    }

    // 4. Create base registry and unmask matrix
    final base = matrixRenderer.createBaseMatrix(version);
    final unmasked = matrix.clone();
    masking.applyMask(
      matrix: unmasked,
      registry: base.registry,
      pattern: maskPattern,
    );

    // 5. Extract raw interleaved codewords from unmasked matrix
    final rawCodewords = matrixRenderer.extractData(
      matrix: unmasked,
      registry: base.registry,
      version: version,
      level: level,
    );

    // 6. De-interleave raw codewords into individual RS blocks
    final rawBlocks = blockInterleaver.deinterleave(
      rawCodewords: rawCodewords,
      version: version,
      level: level,
    );

    // 7. Reed-Solomon Error Correction on each block
    final ecPer = ecCodewordsPerBlock(version.number, level);
    var totalErrors = 0;
    final correctedDataList = <int>[];
    final correctedBlocks = <RsBlock>[];

    for (var b = 0; b < rawBlocks.length; b++) {
      final rawBlock = rawBlocks[b];
      final received = rawBlock.fullBlock;

      final result = rsCodec.correctBlock(
        received: received,
        dataCodewordsCount: rawBlock.dataCodewords.length,
        eccCodewordsCount: ecPer,
      );

      totalErrors += result.errorsCorrected;
      correctedDataList.addAll(result.data);

      correctedBlocks.add(RsBlock(
        blockIndex: b,
        dataCodewords: result.data,
        eccCodewords: rawBlock.eccCodewords,
      ));
    }

    final correctedCodewords = CorrectedCodewords(
      dataCodewords: correctedDataList,
      errorsCorrected: totalErrors,
      blocks: correctedBlocks,
    );

    // 8. Parse bit stream from corrected data codewords into Segments
    final segments = bitStreamCodec.decodeDataCodewords(
      dataCodewords: correctedDataList,
      version: version,
    );

    // 9. Reconstruct full message text
    final textBuffer = StringBuffer();
    for (final s in segments) {
      if (s.mode == Mode.byte) {
        textBuffer.write(utf8.decode(s.bytes!, allowMalformed: true));
      } else if (s.text != null) {
        textBuffer.write(s.text);
      }
    }

    return DecodeResult(
      text: textBuffer.toString(),
      segments: segments,
      matrix: matrix,
      version: version,
      level: level,
      maskPattern: maskPattern,
      formatInfo: formatInfo,
      versionInfo: versionInfo,
      rawCodewords: rawCodewords,
      correctedCodewords: correctedCodewords,
      errorsCorrected: totalErrors,
    );
  }
}
