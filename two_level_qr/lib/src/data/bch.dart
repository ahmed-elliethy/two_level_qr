/// BCH Code utilities for QR Code Format Information BCH(15, 5) and Version Information BCH(18, 6).
class BchCodec {
  BchCodec._();

  /// Generator polynomial for Format Information BCH(15, 5):
  /// $x^{10} + x^8 + x^5 + x^4 + x^2 + x + 1 = 0\text{x}537$.
  static const int formatGenerator = 0x537;

  /// Generator polynomial for Version Information BCH(18, 6):
  /// $x^{12} + x^{11} + x^{10} + x^9 + x^8 + x^5 + x^2 + 1 = 0\text{x}1F25$.
  static const int versionGenerator = 0x1F25;

  /// Format information mask: $0\text{x}5412$.
  static const int formatMask = 0x5412;

  /// Calculates the Hamming distance (number of differing bits) between [a] and [b].
  static int hammingDistance(int a, int b) {
    var diff = a ^ b;
    var count = 0;
    while (diff != 0) {
      count += diff & 1;
      diff >>= 1;
    }
    return count;
  }

  /// Encodes 5-bit format data into 15-bit BCH codeword with 0x5412 mask applied.
  static int encodeFormat(int data5) {
    if (data5 < 0 || data5 > 31) {
      throw ArgumentError.value(data5, 'data5', 'Format data must be 5 bits (0..31)');
    }
    var bits = data5 << 10;
    while (_numBits(bits) > 10) {
      final shift = _numBits(bits) - 11;
      bits ^= formatGenerator << shift;
    }
    return ((data5 << 10) | bits) ^ formatMask;
  }

  /// Decodes a 15-bit format codeword, correcting up to 3 bit errors.
  /// Returns the 5-bit data value (0..31), or null if uncorrectable (>3 errors).
  static int? decodeFormat(int received15) {
    var bestDistance = 999;
    var bestData = -1;

    for (var data = 0; data < 32; data++) {
      final targetCodeword = encodeFormat(data);
      final dist = hammingDistance(received15, targetCodeword);
      if (dist < bestDistance) {
        bestDistance = dist;
        bestData = data;
      }
    }

    if (bestDistance <= 3) {
      return bestData;
    }
    return null;
  }

  /// Encodes a 6-bit version number (7..40) into 18-bit BCH codeword.
  static int encodeVersion(int versionNumber) {
    if (versionNumber < 7 || versionNumber > 40) {
      throw ArgumentError.value(versionNumber, 'versionNumber', 'Version info applies to versions 7..40');
    }
    var bits = versionNumber << 12;
    while (_numBits(bits) > 12) {
      final shift = _numBits(bits) - 13;
      bits ^= versionGenerator << shift;
    }
    return (versionNumber << 12) | bits;
  }

  /// Decodes an 18-bit version codeword, correcting up to 3 bit errors.
  /// Returns the version number (7..40), or null if uncorrectable.
  static int? decodeVersion(int received18) {
    var bestDistance = 999;
    var bestVersion = -1;

    for (var v = 7; v <= 40; v++) {
      final target = encodeVersion(v);
      final dist = hammingDistance(received18, target);
      if (dist < bestDistance) {
        bestDistance = dist;
        bestVersion = v;
      }
    }

    if (bestDistance <= 3) {
      return bestVersion;
    }
    return null;
  }

  static int _numBits(int value) {
    var count = 0;
    var v = value;
    while (v > 0) {
      count++;
      v >>= 1;
    }
    return count;
  }
}
