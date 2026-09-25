import '../domain/error_correction_level.dart';
import '../domain/mask_pattern.dart';
import '../domain/ports.dart';
import '../domain/qr_matrix.dart';
import '../domain/version.dart';
import 'format_info_codec.dart';

/// Implements ISO/IEC 18004 QR Code masking and penalty scoring.
class Masking implements MaskingPort {
  const Masking({this.formatCodec = const FormatInfoCodec()});

  final FormatInfoCodecPort formatCodec;

  @override
  void applyMask({
    required QrMatrix matrix,
    required ModuleRegistry registry,
    required MaskPattern pattern,
  }) {
    final size = matrix.size;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (!registry.isReserved(x, y) && pattern.isMasked(x, y)) {
          matrix.toggle(x, y);
        }
      }
    }
  }

  @override
  int calculatePenalty(QrMatrix matrix) {
    return _penaltyN1(matrix) +
        _penaltyN2(matrix) +
        _penaltyN3(matrix) +
        _penaltyN4(matrix);
  }

  @override
  MaskPattern pickBestMask({
    required QrMatrix baseMatrix,
    required ModuleRegistry registry,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) {
    var bestPenalty = 1 << 30;
    var bestMask = MaskPattern.pattern0;

    for (final pattern in MaskPattern.values) {
      final copy = baseMatrix.clone();
      applyMask(matrix: copy, registry: registry, pattern: pattern);

      // Temporarily place format info for this mask to evaluate true penalty
      final formatInfo = formatCodec.encode(level, pattern);
      _placeFormatInfo(copy, formatInfo.bits15);

      final penalty = calculatePenalty(copy);
      if (penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = pattern;
      }
    }

    return bestMask;
  }

  /// Feature 1: Runs of >= 5 modules of the same color in rows and columns.
  int _penaltyN1(QrMatrix matrix) {
    final size = matrix.size;
    var penalty = 0;

    // Horizontal check
    for (var y = 0; y < size; y++) {
      var runColor = matrix.isDark(0, y);
      var runLen = 1;
      for (var x = 1; x < size; x++) {
        final c = matrix.isDark(x, y);
        if (c == runColor) {
          runLen++;
        } else {
          if (runLen >= 5) penalty += 3 + (runLen - 5);
          runColor = c;
          runLen = 1;
        }
      }
      if (runLen >= 5) penalty += 3 + (runLen - 5);
    }

    // Vertical check
    for (var x = 0; x < size; x++) {
      var runColor = matrix.isDark(x, 0);
      var runLen = 1;
      for (var y = 1; y < size; y++) {
        final c = matrix.isDark(x, y);
        if (c == runColor) {
          runLen++;
        } else {
          if (runLen >= 5) penalty += 3 + (runLen - 5);
          runColor = c;
          runLen = 1;
        }
      }
      if (runLen >= 5) penalty += 3 + (runLen - 5);
    }

    return penalty;
  }

  /// Feature 2: 2x2 blocks of the same color.
  int _penaltyN2(QrMatrix matrix) {
    final size = matrix.size;
    var penalty = 0;
    for (var y = 0; y < size - 1; y++) {
      for (var x = 0; x < size - 1; x++) {
        final c = matrix.isDark(x, y);
        if (matrix.isDark(x + 1, y) == c &&
            matrix.isDark(x, y + 1) == c &&
            matrix.isDark(x + 1, y + 1) == c) {
          penalty += 3;
        }
      }
    }
    return penalty;
  }

  /// Feature 3: Finder-like patterns (1:1:3:1:1 with 4 light modules before or after).
  int _penaltyN3(QrMatrix matrix) {
    final size = matrix.size;
    var penalty = 0;

    // Check rows
    for (var y = 0; y < size; y++) {
      for (var x = 0; x <= size - 11; x++) {
        // Pattern 1: 0000 1011101
        if (!matrix.isDark(x, y) &&
            !matrix.isDark(x + 1, y) &&
            !matrix.isDark(x + 2, y) &&
            !matrix.isDark(x + 3, y) &&
            matrix.isDark(x + 4, y) &&
            !matrix.isDark(x + 5, y) &&
            matrix.isDark(x + 6, y) &&
            matrix.isDark(x + 7, y) &&
            matrix.isDark(x + 8, y) &&
            !matrix.isDark(x + 9, y) &&
            matrix.isDark(x + 10, y)) {
          penalty += 40;
        }
        // Pattern 2: 1011101 0000
        if (matrix.isDark(x, y) &&
            !matrix.isDark(x + 1, y) &&
            matrix.isDark(x + 2, y) &&
            matrix.isDark(x + 3, y) &&
            matrix.isDark(x + 4, y) &&
            !matrix.isDark(x + 5, y) &&
            matrix.isDark(x + 6, y) &&
            !matrix.isDark(x + 7, y) &&
            !matrix.isDark(x + 8, y) &&
            !matrix.isDark(x + 9, y) &&
            !matrix.isDark(x + 10, y)) {
          penalty += 40;
        }
      }
    }

    // Check columns
    for (var x = 0; x < size; x++) {
      for (var y = 0; y <= size - 11; y++) {
        // Pattern 1: 0000 1011101
        if (!matrix.isDark(x, y) &&
            !matrix.isDark(x, y + 1) &&
            !matrix.isDark(x, y + 2) &&
            !matrix.isDark(x, y + 3) &&
            matrix.isDark(x, y + 4) &&
            !matrix.isDark(x, y + 5) &&
            matrix.isDark(x, y + 6) &&
            matrix.isDark(x, y + 7) &&
            matrix.isDark(x, y + 8) &&
            !matrix.isDark(x, y + 9) &&
            matrix.isDark(x, y + 10)) {
          penalty += 40;
        }
        // Pattern 2: 1011101 0000
        if (matrix.isDark(x, y) &&
            !matrix.isDark(x, y + 1) &&
            matrix.isDark(x, y + 2) &&
            matrix.isDark(x, y + 3) &&
            matrix.isDark(x, y + 4) &&
            !matrix.isDark(x, y + 5) &&
            matrix.isDark(x, y + 6) &&
            !matrix.isDark(x, y + 7) &&
            !matrix.isDark(x, y + 8) &&
            !matrix.isDark(x, y + 9) &&
            !matrix.isDark(x, y + 10)) {
          penalty += 40;
        }
      }
    }

    return penalty;
  }

  /// Feature 4: Proportion of dark modules.
  int _penaltyN4(QrMatrix matrix) {
    final size = matrix.size;
    final total = size * size;
    final dark = matrix.countDark();
    final percentage = (dark * 100) / total;
    final prevMultiple = (percentage ~/ 5) * 5;
    final nextMultiple = prevMultiple + 5;
    final d1 = (prevMultiple - 50).abs() ~/ 5;
    final d2 = (nextMultiple - 50).abs() ~/ 5;
    final minDistance = d1 < d2 ? d1 : d2;
    return minDistance * 10;
  }

  void _placeFormatInfo(QrMatrix matrix, int formatBits) {
    final size = matrix.size;
    // Format bits are 15 bits: bit 14 (MSB) to bit 0 (LSB)
    for (var i = 0; i < 15; i++) {
      final isDark = ((formatBits >> (14 - i)) & 1) == 1;
      // Top-left format placement
      final (x1, y1) = _formatPosTopLeft(i);
      matrix.setDark(x1, y1, dark: isDark);

      // Split format placement (bottom-left / top-right)
      final (x2, y2) = _formatPosSplit(i, size);
      matrix.setDark(x2, y2, dark: isDark);
    }
  }

  static (int, int) _formatPosTopLeft(int index) {
    // Top-left: (0,8)..(5,8), (7,8), (8,8), (8,7), (8,5)..(8,0)
    if (index <= 5) return (index, 8);
    if (index == 6) return (7, 8);
    if (index == 7) return (8, 8);
    if (index == 8) return (8, 7);
    return (8, 14 - index);
  }

  static (int, int) _formatPosSplit(int index, int size) {
    // Bottom-left / Top-right
    if (index <= 6) return (8, size - 1 - index);
    return (size - 15 + index, 8);
  }
}
