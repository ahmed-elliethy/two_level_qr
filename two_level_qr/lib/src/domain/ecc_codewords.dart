/// Error correction codewords generated for a block or entire symbol.
class EccCodewords {
  EccCodewords(List<int> bytes) : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;

  int get length => bytes.length;
  int operator [](int index) => bytes[index];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EccCodewords || other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'EccCodewords(count=${bytes.length})';
}
