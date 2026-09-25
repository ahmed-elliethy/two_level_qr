import 'domain/corrected_codewords.dart';
import 'domain/error_correction_level.dart';
import 'domain/format_info.dart';
import 'domain/mask_pattern.dart';
import 'domain/qr_matrix.dart';
import 'domain/raw_codewords.dart';
import 'domain/segment.dart';
import 'domain/version.dart';
import 'domain/version_info.dart';

/// Complete result of a QR Code decode pipeline with all first-class checkpoints.
class DecodeResult {
  const DecodeResult({
    required this.text,
    required this.segments,
    required this.matrix,
    required this.version,
    required this.level,
    required this.maskPattern,
    required this.formatInfo,
    this.versionInfo,
    required this.rawCodewords,
    required this.correctedCodewords,
    required this.errorsCorrected,
  });

  /// The decoded message text.
  final String text;

  /// The parsed segments from the bit stream.
  final List<Segment> segments;

  /// The input QR matrix.
  final QrMatrix matrix;

  /// The QR symbol version detected.
  final QrVersion version;

  /// The error correction level detected.
  final ErrorCorrectionLevel level;

  /// The mask pattern detected and removed.
  final MaskPattern maskPattern;

  /// The decoded and error-corrected Format Information.
  final FormatInfo formatInfo;

  /// The decoded Version Information (for versions >= 7), or null.
  final VersionInfo? versionInfo;

  /// The raw codewords extracted from the matrix before error correction.
  final RawCodewords rawCodewords;

  /// The error-corrected data codewords and RS blocks.
  final CorrectedCodewords correctedCodewords;

  /// Total number of errors corrected across all RS blocks.
  final int errorsCorrected;

  @override
  String toString() =>
      'DecodeResult(text="$text", v${version.number}-${level.label}, errorsCorrected=$errorsCorrected)';
}
