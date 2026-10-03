/// Minimal unsigned 64-bit integer arithmetic (mod 2^64) built from two
/// 32-bit halves.
///
/// Dart's `int` is 64-bit on the VM but a double on the web, so 64-bit
/// constants and wrap-around multiplication cannot be used directly in code
/// that must compile to JavaScript. Every intermediate value here stays below
/// 2^53, which keeps the results bit-identical on all platforms.
///
/// Internal to the package; not exported.
class Uint64 {
  const Uint64(this.hi, this.lo);

  /// Upper 32 bits, in `[0, 2^32)`.
  final int hi;

  /// Lower 32 bits, in `[0, 2^32)`.
  final int lo;

  static const int _mask32 = 0xFFFFFFFF;

  bool get isZero => hi == 0 && lo == 0;

  /// The lower 32 bits as an unsigned value.
  int get low32 => lo;

  Uint64 operator ^(Uint64 other) => Uint64(
        (hi ^ other.hi) & _mask32,
        (lo ^ other.lo) & _mask32,
      );

  /// Logical left shift by [n] bits, `0 <= n < 64`.
  Uint64 shl(int n) {
    if (n == 0) return this;
    if (n >= 32) return Uint64((lo << (n - 32)) & _mask32, 0);
    return Uint64(
      ((hi << n) | (lo >>> (32 - n))) & _mask32,
      (lo << n) & _mask32,
    );
  }

  /// Logical right shift by [n] bits, `0 <= n < 64`.
  Uint64 shr(int n) {
    if (n == 0) return this;
    if (n >= 32) return Uint64(0, hi >>> (n - 32));
    return Uint64(
      hi >>> n,
      ((lo >>> n) | (hi << (32 - n))) & _mask32,
    );
  }

  /// Product mod 2^64, computed with 16-bit limbs so every partial sum stays
  /// exactly representable as a double (< 2^53).
  Uint64 operator *(Uint64 other) {
    final a = _limbs();
    final b = other._limbs();
    final r = List<int>.filled(4, 0);
    var carry = 0;
    for (var k = 0; k < 4; k++) {
      var sum = carry;
      for (var i = 0; i <= k; i++) {
        sum += a[i] * b[k - i];
      }
      // Use arithmetic instead of bit ops: on the web, bit ops truncate
      // their operands to 32 bits.
      r[k] = sum % 0x10000;
      carry = sum ~/ 0x10000;
    }
    return Uint64(r[3] * 0x10000 + r[2], r[1] * 0x10000 + r[0]);
  }

  List<int> _limbs() => [lo & 0xFFFF, lo >>> 16, hi & 0xFFFF, hi >>> 16];

  @override
  bool operator ==(Object other) =>
      other is Uint64 && other.hi == hi && other.lo == lo;

  @override
  int get hashCode => Object.hash(hi, lo);

  @override
  String toString() =>
      '0x${hi.toRadixString(16).padLeft(8, '0')}${lo.toRadixString(16).padLeft(8, '0')}';
}
