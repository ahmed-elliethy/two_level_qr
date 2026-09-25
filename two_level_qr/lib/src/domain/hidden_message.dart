import '../decode_result.dart';
import 'error_correction_level.dart';

/// Thrown when a hidden message cannot fit in the largest QR version (40)
/// for the chosen error-correction level and ratio.
class HiddenMessageCapacityException implements Exception {
  HiddenMessageCapacityException({
    required this.hiddenPayloadBytes,
    required this.totalHiddenBytes,
    required this.maxCapacityBytes,
    required this.level,
    required this.ratio,
  });

  /// Length of the user-provided hidden payload in bytes (excluding the
  /// 2-byte length prefix).
  final int hiddenPayloadBytes;

  /// Total hidden-channel bytes required, including the 2-byte length prefix.
  final int totalHiddenBytes;

  /// Maximum number of hidden-channel bytes available at QR version 40 with
  /// the selected [level] and [ratio].
  final int maxCapacityBytes;

  /// Error-correction level that was used.
  final ErrorCorrectionLevel level;

  /// Ratio that was used.
  final double ratio;

  @override
  String toString() {
    return 'HiddenMessageCapacityException: hidden message is too large '
        '($hiddenPayloadBytes payload bytes / $totalHiddenBytes total bytes, '
        'including the 2-byte length prefix). '
        'Maximum capacity at QR version 40, level ${level.label}, ratio $ratio '
        'is $maxCapacityBytes bytes. Try a shorter hidden message, a higher '
        'error-correction level, or a larger ratio.';
  }
}

/// Options controlling how a hidden message is embedded into the error
/// correction channel of a QR code.
class HiddenEncodeOptions {
  /// Creates options for the hidden message channel.
  ///
  /// [ratio] must be in the range `(0.0, 1.0]`. It controls what fraction of
  /// the Reed-Solomon error budget is used for the hidden message. The
  /// remaining budget is reserved as a safety margin for natural noise and
  /// scanner imperfections.
  const HiddenEncodeOptions({
    required this.key,
    this.ratio = 0.8,
  }) : assert(ratio > 0.0 && ratio <= 1.0, 'ratio must be in (0.0, 1.0]');

  /// Secret key used to derive the pseudo-random positions of the hidden
  /// bytes. The same key must be supplied during extraction.
  final String key;

  /// Fraction of the per-block Reed-Solomon error budget (`t`) that may be
  /// used for hidden data. Defaults to `0.8`, leaving 20 % of `t` (but always
  /// at least one byte error) for real-world noise.
  final double ratio;

  /// Returns a copy of these options with the given fields replaced.
  HiddenEncodeOptions copyWith({String? key, double? ratio}) {
    return HiddenEncodeOptions(
      key: key ?? this.key,
      ratio: ratio ?? this.ratio,
    );
  }
}

/// Result of decoding a two-level QR code that may contain a hidden message.
///
/// The [public] field holds the normal QR payload, which is Reed-Solomon
/// corrected independently of the hidden channel. The [rawErrorBytes] field
/// contains every raw `raw ^ corrected` difference at the key-derived error
/// positions. If the wrong key is used, all hidden fields contain garbage.
class HiddenDecodeResult {
  const HiddenDecodeResult({
    required this.public,
    required this.rawErrorBytes,
    required this.hiddenBytes,
    required this.hiddenText,
  });

  /// The public QR payload (Level 1).
  final DecodeResult public;

  /// All raw byte differences recovered from the keyed error positions,
  /// including the 2-byte length prefix. With the wrong key this is garbage.
  final List<int> rawErrorBytes;

  /// Hidden payload bytes after parsing the 2-byte length prefix from
  /// [rawErrorBytes]. If the prefix is malformed (e.g. wrong key), this still
  /// returns the garbage bytes selected by that prefix.
  final List<int> hiddenBytes;

  /// [hiddenBytes] decoded as UTF-8, with malformed sequences allowed. This
  /// is provided as a convenience; callers that need byte-level secrecy should
  /// inspect [hiddenBytes] or [rawErrorBytes] directly.
  final String hiddenText;

  @override
  String toString() =>
      'HiddenDecodeResult(public="${public.text}", hiddenBytes=${hiddenBytes.length})';
}
