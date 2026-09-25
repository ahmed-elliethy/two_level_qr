import 'error_correction_level.dart';
import 'mask_pattern.dart';

/// Decoded and validated Format Information (ISO/IEC 18004 §8.9).
class FormatInfo {
  const FormatInfo({
    required this.level,
    required this.maskPattern,
    required this.bits15,
  });

  /// The error correction level encoded in the format information.
  final ErrorCorrectionLevel level;

  /// The mask pattern reference.
  final MaskPattern maskPattern;

  /// The 15-bit format sequence (5 data bits + 10 BCH error correction bits, XORed with 0x5412).
  final int bits15;

  /// The 5 raw data bits: (level.formatBits << 3) | maskPattern.bits
  int get dataBits => (level.formatBits << 3) | maskPattern.bits;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormatInfo &&
          other.level == level &&
          other.maskPattern == maskPattern &&
          other.bits15 == bits15;

  @override
  int get hashCode => Object.hash(level, maskPattern, bits15);

  @override
  String toString() =>
      'FormatInfo(level=${level.label}, mask=${maskPattern.bits}, bits15=0x${bits15.toRadixString(16).padLeft(4, '0')})';
}
