import 'bit_buffer.dart';

/// The final interleaved codeword stream ready for matrix module placement,
/// including any trailing remainder bits.
class FinalCodewords {
  FinalCodewords({
    required List<int> bytes,
    required this.remainderBitsCount,
    required this.bitBuffer,
  }) : bytes = List<int>.unmodifiable(bytes);

  /// Interleaved codeword bytes (data interleaved across blocks, followed by ECC interleaved).
  final List<int> bytes;

  /// Number of remainder bits (0..7) appended at the end of the symbol.
  final int remainderBitsCount;

  /// Complete bit buffer of all data/ECC bits plus remainder bits.
  final BitBuffer bitBuffer;

  int get length => bytes.length;
  int operator [](int index) => bytes[index];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FinalCodewords ||
        other.remainderBitsCount != remainderBitsCount ||
        other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(remainderBitsCount, Object.hashAll(bytes));

  @override
  String toString() =>
      'FinalCodewords(bytes=${bytes.length}, remainderBits=$remainderBitsCount)';
}
