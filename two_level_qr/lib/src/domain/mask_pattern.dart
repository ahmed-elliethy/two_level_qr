/// QR Code Mask Patterns (ISO/IEC 18004 §8.8.1).
enum MaskPattern {
  /// (row + column) % 2 == 0
  pattern0(0),

  /// row % 2 == 0
  pattern1(1),

  /// column % 3 == 0
  pattern2(2),

  /// (row + column) % 3 == 0
  pattern3(3),

  /// (row / 2 + column / 3) % 2 == 0
  pattern4(4),

  /// ((row * column) % 2) + ((row * column) % 3) == 0
  pattern5(5),

  /// (((row * column) % 2) + ((row * column) % 3)) % 2 == 0
  pattern6(6),

  /// (((row + column) % 2) + ((row * column) % 3)) % 2 == 0
  pattern7(7);

  const MaskPattern(this.bits);

  /// 3-bit pattern identifier (0..7).
  final int bits;

  /// Returns true if the mask bit is 1 (module should be inverted) at (x, y).
  ///
  /// Note: [x] is the column (0-indexed) and [y] is the row (0-indexed).
  bool isMasked(int x, int y) {
    switch (this) {
      case MaskPattern.pattern0:
        return (y + x) % 2 == 0;
      case MaskPattern.pattern1:
        return y % 2 == 0;
      case MaskPattern.pattern2:
        return x % 3 == 0;
      case MaskPattern.pattern3:
        return (y + x) % 3 == 0;
      case MaskPattern.pattern4:
        return ((y ~/ 2) + (x ~/ 3)) % 2 == 0;
      case MaskPattern.pattern5:
        return ((y * x) % 2) + ((y * x) % 3) == 0;
      case MaskPattern.pattern6:
        return (((y * x) % 2) + ((y * x) % 3)) % 2 == 0;
      case MaskPattern.pattern7:
        return (((y + x) % 2) + ((y * x) % 3)) % 2 == 0;
    }
  }

  static MaskPattern fromBits(int bits) {
    for (final pattern in MaskPattern.values) {
      if (pattern.bits == bits) return pattern;
    }
    throw ArgumentError.value(bits, 'bits', 'Invalid mask pattern bits (0..7)');
  }
}
