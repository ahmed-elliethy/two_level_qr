/// QR data-encoding modes (ISO/IEC 18004, §8.3).
enum Mode {
  /// Digits `0-9` only. 10 bits pack into 3 characters.
  numeric(0x1, '0001'),

  /// The 45-character QR alphanumeric set. 11 bits pack 2 characters.
  alphanumeric(0x2, '0010'),

  /// Arbitrary byte payload (usually UTF-8). 8 bits per byte.
  byte(0x4, '0100'),

  /// Shift-JIS Kanji, 13 bits per character.
  kanji(0x8, '1000'),

  /// Extended Channel Interpretation header mode.
  eci(0x7, '0111'),

  /// End-of-message marker.
  terminator(0x0, '0000');

  const Mode(this.bits, this.binaryLabel);

  /// 4-bit mode indicator value.
  final int bits;

  /// Binary representation of the 4-bit indicator (e.g. '0001').
  final String binaryLabel;

  String get indicator => binaryLabel;

  /// Character-count-indicator bit width for a given version number
  /// (ISO/IEC 18004 Table 3).
  int charCountBits(int version) {
    switch (this) {
      case Mode.numeric:
        return version <= 9 ? 10 : (version <= 26 ? 12 : 14);
      case Mode.alphanumeric:
        return version <= 9 ? 9 : (version <= 26 ? 11 : 13);
      case Mode.byte:
        return version <= 9 ? 8 : (version <= 26 ? 16 : 16);
      case Mode.kanji:
        return version <= 9 ? 8 : (version <= 26 ? 10 : 12);
      case Mode.eci:
      case Mode.terminator:
        return 0;
    }
  }
}
