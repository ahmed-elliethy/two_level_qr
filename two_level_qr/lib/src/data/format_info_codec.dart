import '../domain/error_correction_level.dart';
import '../domain/format_info.dart';
import '../domain/mask_pattern.dart';
import '../domain/ports.dart';
import 'bch.dart';

/// Codec for encoding and decoding 15-bit Format Information.
class FormatInfoCodec implements FormatInfoCodecPort {
  const FormatInfoCodec();

  @override
  FormatInfo encode(ErrorCorrectionLevel level, MaskPattern maskPattern) {
    final data5 = (level.formatBits << 3) | maskPattern.bits;
    final bits15 = BchCodec.encodeFormat(data5);
    return FormatInfo(
      level: level,
      maskPattern: maskPattern,
      bits15: bits15,
    );
  }

  @override
  FormatInfo decode(int formatBits) {
    final data5 = BchCodec.decodeFormat(formatBits);
    if (data5 == null) {
      throw FormatException('Invalid or uncorrectable format information bits: 0x${formatBits.toRadixString(16)}');
    }
    final levelBits = (data5 >> 3) & 0x03;
    final maskBits = data5 & 0x07;

    final level = ErrorCorrectionLevel.fromFormatBits(levelBits);
    final maskPattern = MaskPattern.fromBits(maskBits);

    return FormatInfo(
      level: level,
      maskPattern: maskPattern,
      bits15: formatBits,
    );
  }
}
