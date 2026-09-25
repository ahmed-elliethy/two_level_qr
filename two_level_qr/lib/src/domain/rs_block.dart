/// A single Reed-Solomon block containing data codewords and its associated ECC codewords.
class RsBlock {
  RsBlock({
    required this.blockIndex,
    required List<int> dataCodewords,
    required List<int> eccCodewords,
  })  : dataCodewords = List<int>.unmodifiable(dataCodewords),
        eccCodewords = List<int>.unmodifiable(eccCodewords);

  final int blockIndex;
  final List<int> dataCodewords;
  final List<int> eccCodewords;

  int get totalCodewords => dataCodewords.length + eccCodewords.length;

  /// Full codeword sequence for this block (data followed by ECC).
  List<int> get fullBlock => [...dataCodewords, ...eccCodewords];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RsBlock ||
        other.blockIndex != blockIndex ||
        other.dataCodewords.length != dataCodewords.length ||
        other.eccCodewords.length != eccCodewords.length) {
      return false;
    }
    for (var i = 0; i < dataCodewords.length; i++) {
      if (dataCodewords[i] != other.dataCodewords[i]) return false;
    }
    for (var i = 0; i < eccCodewords.length; i++) {
      if (eccCodewords[i] != other.eccCodewords[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(blockIndex, Object.hashAll(dataCodewords), Object.hashAll(eccCodewords));

  @override
  String toString() =>
      'RsBlock(#$blockIndex, data=${dataCodewords.length}, ecc=${eccCodewords.length})';
}
