import 'rs_block.dart';

/// The result of Reed-Solomon error correction and block de-interleaving.
class CorrectedCodewords {
  CorrectedCodewords({
    required List<int> dataCodewords,
    required this.errorsCorrected,
    required List<RsBlock> blocks,
  })  : dataCodewords = List<int>.unmodifiable(dataCodewords),
        blocks = List<RsBlock>.unmodifiable(blocks);

  /// Error-corrected data codewords.
  final List<int> dataCodewords;

  /// Total number of byte errors detected and corrected across all RS blocks.
  final int errorsCorrected;

  /// The individual corrected RS blocks.
  final List<RsBlock> blocks;

  int get length => dataCodewords.length;
  int operator [](int index) => dataCodewords[index];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CorrectedCodewords ||
        other.errorsCorrected != errorsCorrected ||
        other.dataCodewords.length != dataCodewords.length ||
        other.blocks.length != blocks.length) {
      return false;
    }
    for (var i = 0; i < dataCodewords.length; i++) {
      if (dataCodewords[i] != other.dataCodewords[i]) return false;
    }
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i] != other.blocks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        errorsCorrected,
        Object.hashAll(dataCodewords),
        Object.hashAll(blocks),
      );

  @override
  String toString() =>
      'CorrectedCodewords(count=${dataCodewords.length}, errorsCorrected=$errorsCorrected)';
}
