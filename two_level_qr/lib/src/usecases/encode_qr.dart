import 'dart:convert';

import '../data/bit_stream_codec.dart';
import '../data/block_interleaver.dart';
import '../data/format_info_codec.dart';
import '../data/masking.dart';
import '../data/matrix_renderer.dart';
import '../data/reed_solomon.dart';
import '../data/version_info_codec.dart';
import '../domain/data_codewords.dart';
import '../domain/error_correction_level.dart';
import '../domain/mask_pattern.dart';
import '../domain/mode.dart';
import '../domain/ports.dart';
import '../domain/rs_block.dart';
import '../domain/segment.dart';
import '../domain/version.dart';
import '../encode_result.dart';

/// Clean-architecture use case implementing the complete QR Code encode pipeline.
class EncodeQr {
  EncodeQr({
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

  /// Executes the complete QR encoding pipeline from [text] (or explicit [segments]).
  EncodeResult execute({
    required String text,
    List<Segment>? segments,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.medium,
    int? explicitVersion,
    MaskPattern? explicitMask,
  }) {
    // 1. Determine segments
    final effectiveSegments = segments ?? autoSegment(text);

    // 2. Determine target version
    final QrVersion version;
    if (explicitVersion != null) {
      version = QrVersion(explicitVersion);
    } else {
      version = _findVersionForSegments(effectiveSegments, level);
    }

    // 3. Encode data codewords
    final dataCodewords = bitStreamCodec.encodeSegments(
      segments: effectiveSegments,
      version: version,
      level: level,
    );

    // 4. Compute RS ECC and interleave blocks
    final finalCodewords = blockInterleaver.interleave(
      dataCodewords: dataCodewords,
      version: version,
      level: level,
      rsCodec: rsCodec,
    );

    // Reconstruct blocks for inspection in EncodeResult
    final rsBlocks = _reconstructBlocks(dataCodewords, version, level);

    // 5. Create base matrix and place data bits
    final base = matrixRenderer.createBaseMatrix(version);
    matrixRenderer.placeData(
      matrix: base.matrix,
      registry: base.registry,
      finalCodewords: finalCodewords,
    );

    // 6. Place Version Information (versions >= 7)
    if (version.number >= 7) {
      final versionInfo = versionCodec.encode(version);
      matrixRenderer.placeVersionInfo(
        matrix: base.matrix,
        versionInfo: versionInfo,
      );
    }

    // 7. Pick & Apply Mask
    final maskPattern = explicitMask ??
        masking.pickBestMask(
          baseMatrix: base.matrix,
          registry: base.registry,
          version: version,
          level: level,
        );

    masking.applyMask(
      matrix: base.matrix,
      registry: base.registry,
      pattern: maskPattern,
    );

    // 8. Place Format Information
    final formatInfo = formatCodec.encode(level, maskPattern);
    matrixRenderer.placeFormatInfo(
      matrix: base.matrix,
      formatInfo: formatInfo,
    );

    return EncodeResult(
      text: text,
      segments: effectiveSegments,
      version: version,
      level: level,
      dataCodewords: dataCodewords,
      rsBlocks: rsBlocks,
      finalCodewords: finalCodewords,
      maskPattern: maskPattern,
      matrix: base.matrix,
    );
  }

  /// Automatically segment input string into the most efficient QR Mode.
  static List<Segment> autoSegment(String text) {
    if (text.isEmpty) {
      return [Segment.byte(const [])];
    }

    // Check if numeric
    var isNumeric = true;
    for (final cu in text.codeUnits) {
      if (cu < 0x30 || cu > 0x39) {
        isNumeric = false;
        break;
      }
    }
    if (isNumeric) {
      return [Segment.numeric(text)];
    }

    // Check if alphanumeric
    var isAlphanumeric = true;
    for (var i = 0; i < text.length; i++) {
      if (alphanumericValue(text[i]) == null) {
        isAlphanumeric = false;
        break;
      }
    }
    if (isAlphanumeric) {
      return [Segment.alphanumeric(text)];
    }

    // Default to UTF-8 Byte mode
    return [Segment.byte(utf8.encode(text))];
  }

  QrVersion _findVersionForSegments(List<Segment> segments, ErrorCorrectionLevel level) {
    for (var v = 1; v <= 40; v++) {
      final version = QrVersion(v);
      final cap = dataCodewordsCapacity(v, level);
      var requiredBits = 0;
      for (final s in segments) {
        requiredBits += 4; // mode indicator
        requiredBits += s.mode.charCountBits(v);
        switch (s.mode) {
          case Mode.numeric:
            requiredBits += (s.characterCount ~/ 3) * 10;
            final rem = s.characterCount % 3;
            if (rem == 2) requiredBits += 7;
            if (rem == 1) requiredBits += 4;
            break;
          case Mode.alphanumeric:
            requiredBits += (s.characterCount ~/ 2) * 11;
            if (s.characterCount % 2 == 1) requiredBits += 6;
            break;
          case Mode.byte:
            requiredBits += s.characterCount * 8;
            break;
          case Mode.kanji:
            requiredBits += s.characterCount * 13;
            break;
          case Mode.eci:
          case Mode.terminator:
            break;
        }
      }
      // Add terminator bits (up to 4)
      final withTerminator = requiredBits + 4;
      final requiredBytes = (withTerminator + 7) ~/ 8;
      if (requiredBytes <= cap) {
        return version;
      }
    }
    throw ArgumentError('Input payload is too large to fit in any QR Code version for level ${level.label}');
  }

  List<RsBlock> _reconstructBlocks(DataCodewords dataCodewords, QrVersion version, ErrorCorrectionLevel level) {
    final vNum = version.number;
    final structure = blockStructure(vNum, level);
    final count1 = structure[0];
    final data1 = structure[1];
    final count2 = structure[2];
    final data2 = structure[3];
    final totalBlocks = count1 + count2;
    final ecPer = ecCodewordsPerBlock(vNum, level);

    final blocks = <RsBlock>[];
    var offset = 0;
    for (var b = 0; b < totalBlocks; b++) {
      final len = (b < count1) ? data1 : data2;
      final blockData = dataCodewords.bytes.sublist(offset, offset + len);
      offset += len;
      final ecc = rsCodec.generateEcc(data: blockData, eccCodewordsCount: ecPer);
      blocks.add(RsBlock(blockIndex: b, dataCodewords: blockData, eccCodewords: ecc.bytes));
    }
    return blocks;
  }
}
