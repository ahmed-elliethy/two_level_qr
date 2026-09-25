/// A growable, immutable-in-intent buffer of bits, MSB-first.
///
/// Used to build the QR bit stream (mode indicators, character counts,
/// encoded payload, terminator and pad bits).
class BitBuffer {
  final List<int> _bits;

  BitBuffer() : _bits = <int>[];

  BitBuffer.fromBits(Iterable<int> bits) : _bits = bits.toList(growable: true);

  /// Number of bits currently buffered.
  int get length => _bits.length;

  /// Number of whole bytes represented by [toBytes] (truncating a trailing
  /// partial byte is not allowed — throws if [length] % 8 != 0).
  int get byteLength {
    if (_bits.length % 8 != 0) {
      throw StateError('BitBuffer length ${_bits.length} is not byte-aligned');
    }
    return _bits.length ~/ 8;
  }

  bool get isEmpty => _bits.isEmpty;

  /// Returns an unmodifiable view of the bits (each 0 or 1), index 0 = first
  /// written bit.
  List<int> get bits => List.unmodifiable(_bits);

  void appendBit(int bit) {
    if (bit != 0 && bit != 1) {
      throw ArgumentError.value(bit, 'bit', 'must be 0 or 1');
    }
    _bits.add(bit);
  }

  /// Appends the [numBits] least-significant bits of [value], MSB first.
  void appendBits(int value, int numBits) {
    if (numBits < 0 || numBits > 32) {
      throw ArgumentError.value(numBits, 'numBits', 'must be in 0..32');
    }
    if (value < 0 || (numBits < 32 && value >> numBits != 0)) {
      throw ArgumentError.value(
          value, 'value', 'does not fit in $numBits bits');
    }
    for (var i = numBits - 1; i >= 0; i--) {
      _bits.add((value >> i) & 1);
    }
  }

  /// Appends all bits of an already-built buffer.
  void appendBuffer(BitBuffer other) {
    _bits.addAll(other._bits);
  }

  /// Pads with zero bits until the length is a multiple of 8.
  void padToByteBoundary() {
    while (_bits.length % 8 != 0) {
      _bits.add(0);
    }
  }

  /// The buffer contents as bytes (MSB-first per byte). Requires byte
  /// alignment.
  Uint8ListLike toBytes() {
    padToByteBoundary();
    final out = List<int>.filled(_bits.length ~/ 8, 0);
    for (var i = 0; i < _bits.length; i++) {
      if (_bits[i] == 1) out[i >> 3] |= 1 << (7 - (i & 7));
    }
    return Uint8ListLike(out);
  }

  @override
  String toString() => _bits.join();
}

/// Minimal byte-list wrapper so the domain layer stays free of `dart:typed_data`
/// imports while still exposing an ordered, indexable byte sequence.
class Uint8ListLike {
  Uint8ListLike(List<int> bytes) : _bytes = List<int>.unmodifiable(bytes);

  final List<int> _bytes;

  int get length => _bytes.length;
  int operator [](int index) => _bytes[index];
  List<int> toList() => List<int>.from(_bytes);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Uint8ListLike || other._bytes.length != _bytes.length) {
      return false;
    }
    for (var i = 0; i < _bytes.length; i++) {
      if (_bytes[i] != other._bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() =>
      'Uint8ListLike(${_bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})';
}
