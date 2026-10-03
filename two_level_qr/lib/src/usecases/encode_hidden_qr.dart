import 'dart:convert';

import '../data/keyed_error_scheduler.dart';
import '../domain/error_correction_level.dart';
import '../domain/final_codewords.dart';
import '../domain/hidden_message.dart';
import '../domain/mask_pattern.dart';
import '../domain/qr_matrix.dart';
import '../domain/rs_block.dart';
import '../domain/version.dart';
import '../encode_result.dart';
import 'encode_qr.dart';

/// Use case that encodes a public QR payload together with a keyed hidden
/// message embedded in the Reed-Solomon error channel.
class EncodeHiddenQr {
  EncodeHiddenQr({
    EncodeQr? encodeQr,
  }) : _encodeQr = encodeQr ?? EncodeQr();

  final EncodeQr _encodeQr;

  /// Encodes [publicText] as the normal QR payload and hides [hiddenText]
  /// inside the error-correction channel using [options.key].
  ///
  /// The hidden message is prefixed with a 2-byte big-endian length and then
  /// embedded as deliberate byte errors at key-derived positions. The
  /// [options.ratio] controls what fraction of the RS error budget is used.
  ///
  /// If [explicitVersion] is not provided and the hidden message does not fit
  /// in the QR version automatically selected for [publicText], the encoder
  /// tries progressively larger versions up to 40. If [explicitVersion] is
  /// provided and the hidden message does not fit, an [ArgumentError] is
  /// thrown.
  EncodeResult execute({
    required String publicText,
    required String hiddenText,
    required HiddenEncodeOptions options,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
    int? explicitVersion,
    MaskPattern? explicitMask,
  }) {
    // Build hidden payload: 2-byte length prefix + UTF-8 bytes.
    final hiddenUtf8 = utf8.encode(hiddenText);
    return executeWithPayload(
      publicText: publicText,
      hiddenText: hiddenText,
      payload: hiddenUtf8,
      options: options,
      level: level,
      explicitVersion: explicitVersion,
      explicitMask: explicitMask,
    );
  }

  /// Embeds an arbitrary [payload] (for example an encrypted envelope) in
  /// the hidden channel of a QR code carrying [publicText].
  ///
  /// The channel bytes are `[len_hi, len_lo] || payload`, scheduled at
  /// key-derived positions and limited per block by [HiddenEncodeOptions.ratio].
  /// [hiddenText] is only recorded in the returned [EncodeResult].
  ///
  /// [userPayloadBytes] and [overheadBytes] describe how [payload] splits into
  /// the caller's message and framing/cipher overhead; they are used only in
  /// capacity error messages. By default the whole payload is the message.
  ///
  /// Version selection follows [execute]: with [explicitVersion] a payload
  /// that does not fit throws an [ArgumentError]; otherwise versions are
  /// tried upward to 40 and [HiddenMessageCapacityException] is thrown if
  /// none fits.
  EncodeResult executeWithPayload({
    required String publicText,
    required String hiddenText,
    required List<int> payload,
    required HiddenEncodeOptions options,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
    int? explicitVersion,
    MaskPattern? explicitMask,
    int? userPayloadBytes,
    int overheadBytes = 0,
    int? hiddenCipherSchemeId,
  }) {
    if (payload.length > 0xFFFF) {
      throw ArgumentError(
        'Hidden message is too long: ${payload.length} bytes (max 65535).',
      );
    }
    final hiddenBytes = <int>[
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
      ...payload,
    ];
    final sizes = _PayloadSizes(
      userBytes: userPayloadBytes ?? payload.length,
      overheadBytes: overheadBytes,
      totalBytes: hiddenBytes.length,
    );

    // 1. Determine the minimum version required for the public payload.
    final minVersion = _findMinimumVersion(
      publicText: publicText,
      level: level,
      explicitVersion: explicitVersion,
    );

    // 2. Try encoding, bumping the version if the hidden message doesn't fit.
    if (explicitVersion != null) {
      return _tryEncodeVersion(
        publicText: publicText,
        hiddenText: hiddenText,
        hiddenBytes: hiddenBytes,
        sizes: sizes,
        options: options,
        level: level,
        version: minVersion,
        explicitMask: explicitMask,
        hiddenCipherSchemeId: hiddenCipherSchemeId,
      );
    }

    for (var v = minVersion.number; v <= 40; v++) {
      try {
        return _tryEncodeVersion(
          publicText: publicText,
          hiddenText: hiddenText,
          hiddenBytes: hiddenBytes,
          sizes: sizes,
          options: options,
          level: level,
          version: QrVersion(v),
          explicitMask: explicitMask,
          hiddenCipherSchemeId: hiddenCipherSchemeId,
        );
      } on _HiddenCapacityError {
        // Capacity exceeded at this version; try the next one.
      }
    }

    throw HiddenMessageCapacityException(
      hiddenPayloadBytes: sizes.userBytes,
      totalHiddenBytes: sizes.totalBytes,
      maxCapacityBytes: _maxCapacityAtV40(options: options, level: level),
      level: level,
      ratio: options.ratio,
      overheadBytes: overheadBytes,
    );
  }

  int _maxCapacityAtV40({
    required HiddenEncodeOptions options,
    required ErrorCorrectionLevel level,
  }) {
    final scheduler =
        KeyedErrorScheduler(key: options.key, ratio: options.ratio);
    final clean = _encodeQr.execute(
      text: 'x',
      level: level,
      explicitVersion: 40,
    );
    return scheduler.computeCapacity(clean.rsBlocks).totalBytes;
  }

  QrVersion _findMinimumVersion({
    required String publicText,
    required ErrorCorrectionLevel level,
    int? explicitVersion,
  }) {
    if (explicitVersion != null) {
      return QrVersion(explicitVersion);
    }
    final enc = _encodeQr.execute(text: publicText, level: level);
    return enc.version;
  }

  EncodeResult _tryEncodeVersion({
    required String publicText,
    required String hiddenText,
    required List<int> hiddenBytes,
    required _PayloadSizes sizes,
    required HiddenEncodeOptions options,
    required ErrorCorrectionLevel level,
    required QrVersion version,
    MaskPattern? explicitMask,
    int? hiddenCipherSchemeId,
  }) {
    // 1. Encode the public payload normally to obtain clean RS blocks.
    final clean = _encodeQr.execute(
      text: publicText,
      level: level,
      explicitVersion: version.number,
      explicitMask: explicitMask,
    );

    final blocks = clean.rsBlocks;
    final scheduler = KeyedErrorScheduler(
      key: options.key,
      ratio: options.ratio,
    );

    // 2. Verify capacity, then schedule key-dependent positions.
    final capacity = scheduler.computeCapacity(blocks).totalBytes;
    if (sizes.totalBytes > capacity) {
      throw _HiddenCapacityError(
        'Hidden channel needs ${sizes.totalBytes} bytes '
        '(${sizes.userBytes} message + 2 length prefix'
        '${sizes.overheadBytes > 0 ? ' + ${sizes.overheadBytes} encryption overhead' : ''}'
        '), but v${version.number}-${level.label} at ratio ${options.ratio} '
        'holds only $capacity bytes.',
      );
    }
    final positions = scheduler.schedulePositions(
      blocks: blocks,
      count: hiddenBytes.length,
    );

    // 3. Inject hidden bytes as errors into the clean RS blocks.
    final stegoBlocks = _injectErrors(blocks, positions, hiddenBytes);

    // 4. Re-interleave the modified blocks.
    final stegoFinalCodewords = _encodeQr.blockInterleaver.interleaveBlocks(
      blocks: stegoBlocks,
      version: clean.version,
      level: clean.level,
    );

    // 5. Render the final QR matrix from the stego final codewords.
    final stegoMatrix = _renderMatrix(
      finalCodewords: stegoFinalCodewords,
      version: clean.version,
      level: clean.level,
      explicitMask: clean.maskPattern,
    );

    return EncodeResult(
      text: publicText,
      segments: clean.segments,
      version: clean.version,
      level: clean.level,
      dataCodewords: clean.dataCodewords,
      rsBlocks: stegoBlocks,
      finalCodewords: stegoFinalCodewords,
      maskPattern: clean.maskPattern,
      matrix: stegoMatrix,
      hiddenText: hiddenText,
      hiddenBytes: hiddenBytes,
      hiddenCipherSchemeId: hiddenCipherSchemeId,
    );
  }

  List<RsBlock> _injectErrors(
    List<RsBlock> blocks,
    List<HiddenErrorPosition> positions,
    List<int> hiddenBytes,
  ) {
    final modified = List<RsBlock>.from(blocks);

    for (var i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final secretByte = hiddenBytes[i];
      final block = modified[pos.blockIndex];

      final newData = List<int>.from(block.dataCodewords);
      newData[pos.position] ^= secretByte;

      modified[pos.blockIndex] = RsBlock(
        blockIndex: block.blockIndex,
        dataCodewords: newData,
        eccCodewords: block.eccCodewords,
      );
    }

    return modified;
  }

  QrMatrix _renderMatrix({
    required FinalCodewords finalCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
    required MaskPattern explicitMask,
  }) {
    final base = _encodeQr.matrixRenderer.createBaseMatrix(version);
    _encodeQr.matrixRenderer.placeData(
      matrix: base.matrix,
      registry: base.registry,
      finalCodewords: finalCodewords,
    );

    if (version.number >= 7) {
      final versionInfo = _encodeQr.versionCodec.encode(version);
      _encodeQr.matrixRenderer.placeVersionInfo(
        matrix: base.matrix,
        versionInfo: versionInfo,
      );
    }

    _encodeQr.masking.applyMask(
      matrix: base.matrix,
      registry: base.registry,
      pattern: explicitMask,
    );

    final formatInfo = _encodeQr.formatCodec.encode(level, explicitMask);
    _encodeQr.matrixRenderer.placeFormatInfo(
      matrix: base.matrix,
      formatInfo: formatInfo,
    );

    return base.matrix;
  }
}

/// Capacity overflow at one version; distinct from other [ArgumentError]s so
/// the automatic version search only retries on capacity problems.
class _HiddenCapacityError extends ArgumentError {
  _HiddenCapacityError(super.message);
}

class _PayloadSizes {
  const _PayloadSizes({
    required this.userBytes,
    required this.overheadBytes,
    required this.totalBytes,
  });

  final int userBytes;
  final int overheadBytes;
  final int totalBytes;
}
