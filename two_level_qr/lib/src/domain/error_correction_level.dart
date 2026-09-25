/// Error correction levels as defined by ISO/IEC 18004.
enum ErrorCorrectionLevel {
  /// ~7% recovery capability. Format-info data bits: `01`.
  low(0, 'L', 0x01),

  /// ~15% recovery capability. Format-info data bits: `00`.
  medium(1, 'M', 0x00),

  /// ~25% recovery capability. Format-info data bits: `11`.
  quartile(2, 'Q', 0x03),

  /// ~30% recovery capability. Format-info data bits: `10`.
  high(3, 'H', 0x02);

  const ErrorCorrectionLevel(this.ordinal, this.label, this.formatBits);

  /// Index used to look up EC codeword counts in the version tables
  /// (order L, M, Q, H).
  final int ordinal;

  /// Human-readable single-letter label.
  final String label;

  /// The 2-bit ECC indicator written into the format information.
  final int formatBits;

  static ErrorCorrectionLevel fromFormatBits(int bits) {
    for (final level in ErrorCorrectionLevel.values) {
      if (level.formatBits == bits) return level;
    }
    throw ArgumentError('Invalid ECC format bits: $bits');
  }
}
