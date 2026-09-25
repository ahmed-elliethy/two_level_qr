import 'domain/data_codewords.dart';
import 'domain/error_correction_level.dart';
import 'domain/final_codewords.dart';
import 'domain/mask_pattern.dart';
import 'domain/qr_matrix.dart';
import 'domain/rs_block.dart';
import 'domain/segment.dart';
import 'domain/version.dart';

/// Complete result of a QR Code encode pipeline with all first-class checkpoints.
class EncodeResult {
  const EncodeResult({
    required this.text,
    required this.segments,
    required this.version,
    required this.level,
    required this.dataCodewords,
    required this.rsBlocks,
    required this.finalCodewords,
    required this.maskPattern,
    required this.matrix,
    this.hiddenText,
    this.hiddenBytes,
  });

  /// The original input text or message.
  final String text;

  /// The list of mode-encoded segments (numeric, alphanumeric, byte, kanji).
  final List<Segment> segments;

  /// The QR symbol version selected.
  final QrVersion version;

  /// The error correction level used.
  final ErrorCorrectionLevel level;

  /// The data codewords stream before RS ECC calculation and interleaving.
  final DataCodewords dataCodewords;

  /// The individual Reed-Solomon blocks (data + ECC per block).
  final List<RsBlock> rsBlocks;

  /// The interleaved final codewords including remainder bits.
  final FinalCodewords finalCodewords;

  /// The mask pattern chosen by penalty optimization.
  final MaskPattern maskPattern;

  /// The final, fully masked QR matrix with all function patterns and format/version info.
  final QrMatrix matrix;

  /// Hidden message text, if this encode result was produced by a two-level
  /// encode with a hidden channel. `null` for normal QR encodes.
  final String? hiddenText;

  /// Hidden message bytes (including the 2-byte length prefix), if this encode
  /// result was produced by a two-level encode with a hidden channel.
  /// `null` for normal QR encodes.
  final List<int>? hiddenBytes;

  @override
  String toString() =>
      'EncodeResult(v${version.number}-${level.label}, mask=${maskPattern.bits}, size=${matrix.size}x${matrix.size})';
}
