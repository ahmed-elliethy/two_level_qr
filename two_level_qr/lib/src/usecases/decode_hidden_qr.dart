import 'dart:convert';

import '../data/keyed_error_scheduler.dart';
import '../domain/hidden_message.dart';
import '../domain/qr_matrix.dart';
import '../domain/rs_block.dart';
import 'decode_qr.dart';

/// Use case that decodes a public QR payload and extracts a keyed hidden
/// message from the Reed-Solomon error channel.
class DecodeHiddenQr {
  DecodeHiddenQr({
    DecodeQr? decodeQr,
  }) : _decodeQr = decodeQr ?? DecodeQr();

  final DecodeQr _decodeQr;

  /// Decodes [matrix] and extracts the hidden message using [key].
  ///
  /// [ratio] must match the value used during encoding (default `0.8`).
  ///
  /// If the key is wrong, the returned [HiddenDecodeResult.hiddenBytes] and
  /// [HiddenDecodeResult.hiddenText] contain garbage bytes rather than the
  /// original secret; no exception is thrown.
  HiddenDecodeResult execute(
    QrMatrix matrix, {
    required String key,
    double ratio = 0.8,
  }) {
    // 1. Decode the public payload normally and obtain corrected blocks.
    final public = _decodeQr.execute(matrix);

    // 2. Reconstruct the raw blocks from the raw codewords.
    final rawBlocks = _decodeQr.blockInterleaver.deinterleave(
      rawCodewords: public.rawCodewords,
      version: public.version,
      level: public.level,
    );

    final correctedBlocks = public.correctedCodewords.blocks;

    // 3. Schedule all key-derived error positions.
    final scheduler = KeyedErrorScheduler(key: key, ratio: ratio);
    final capacity = scheduler.computeCapacity(correctedBlocks);
    final positions = scheduler.schedulePositions(
      blocks: correctedBlocks,
      count: capacity.totalBytes,
    );

    // 4. Extract the raw error bytes.
    final rawErrorBytes = _extractErrorBytes(
      rawBlocks: rawBlocks,
      correctedBlocks: correctedBlocks,
      positions: positions,
    );

    // 5. Parse the 2-byte length prefix and slice the payload.
    final (hiddenBytes, hiddenText) = _parseHiddenPayload(rawErrorBytes);

    return HiddenDecodeResult(
      public: public,
      rawErrorBytes: rawErrorBytes,
      hiddenBytes: hiddenBytes,
      hiddenText: hiddenText,
    );
  }

  List<int> _extractErrorBytes({
    required List<RsBlock> rawBlocks,
    required List<RsBlock> correctedBlocks,
    required List<HiddenErrorPosition> positions,
  }) {
    return positions.map((pos) {
      final raw = rawBlocks[pos.blockIndex].fullBlock[pos.position];
      final corrected = correctedBlocks[pos.blockIndex].fullBlock[pos.position];
      return raw ^ corrected;
    }).toList();
  }

  (List<int>, String) _parseHiddenPayload(List<int> rawErrorBytes) {
    if (rawErrorBytes.length < 2) {
      return (
        rawErrorBytes,
        utf8.decode(rawErrorBytes, allowMalformed: true),
      );
    }

    final length = (rawErrorBytes[0] << 8) | rawErrorBytes[1];
    final end = 2 + length;
    final hiddenBytes = rawErrorBytes.sublist(
      2,
      end > rawErrorBytes.length ? rawErrorBytes.length : end,
    );
    return (
      hiddenBytes,
      utf8.decode(hiddenBytes, allowMalformed: true),
    );
  }
}
