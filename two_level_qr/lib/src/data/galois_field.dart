/// Galois Field GF(256) arithmetic with primitive polynomial
/// $x^8 + x^4 + x^3 + x^2 + 1$ ($0\text{x}11D = 285$) and generator $\alpha = 2$.
class GaloisField256 {
  GaloisField256._() {
    var value = 1;
    for (var i = 0; i < 255; i++) {
      _expTable[i] = value;
      _logTable[value] = i;
      value <<= 1;
      if (value >= 256) {
        value ^= 0x11D;
      }
    }
    for (var i = 255; i < 512; i++) {
      _expTable[i] = _expTable[i - 255];
    }
  }

  static final GaloisField256 instance = GaloisField256._();

  final List<int> _expTable = List<int>.filled(512, 0);
  final List<int> _logTable = List<int>.filled(256, 0);

  /// $a + b$ in GF(256) (equivalent to XOR).
  int add(int a, int b) => a ^ b;

  /// $a - b$ in GF(256) (equivalent to XOR).
  int subtract(int a, int b) => a ^ b;

  /// $\alpha^power$.
  int exp(int power) => _expTable[power];

  /// $\log_\alpha(value)$.
  int log(int value) {
    if (value == 0) {
      throw ArgumentError.value(value, 'value', 'log(0) is undefined in GF(256)');
    }
    return _logTable[value];
  }

  /// Multiplicative inverse of [a] ($a^{-1}$).
  int inverse(int a) {
    if (a == 0) {
      throw ArgumentError.value(a, 'a', '0 has no multiplicative inverse');
    }
    return _expTable[255 - _logTable[a]];
  }

  /// $a \times b$ in GF(256).
  int multiply(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _expTable[_logTable[a] + _logTable[b]];
  }

  /// $a / b$ in GF(256).
  int divide(int a, int b) {
    if (b == 0) {
      throw ArgumentError.value(b, 'b', 'Division by zero in GF(256)');
    }
    if (a == 0) return 0;
    return _expTable[(_logTable[a] - _logTable[b] + 255) % 255];
  }

  /// Evaluates polynomial [poly] at point [x] using Horner's method.
  /// Coefficients are highest degree first: `poly[0]*x^(n-1) + ... + poly[n-1]`.
  int evaluatePoly(List<int> poly, int x) {
    if (poly.isEmpty) return 0;
    var result = poly[0];
    for (var i = 1; i < poly.length; i++) {
      result = add(multiply(result, x), poly[i]);
    }
    return result;
  }

  /// Multiplies two polynomials [a] and [b].
  List<int> multiplyPoly(List<int> a, List<int> b) {
    if (a.isEmpty || b.isEmpty) return const [];
    if ((a.length == 1 && a[0] == 0) || (b.length == 1 && b[0] == 0)) {
      return [0];
    }
    final result = List<int>.filled(a.length + b.length - 1, 0);
    for (var i = 0; i < a.length; i++) {
      for (var j = 0; j < b.length; j++) {
        result[i + j] ^= multiply(a[i], b[j]);
      }
    }
    return result;
  }

  /// Scales polynomial [poly] by constant scalar [scalar].
  List<int> scalePoly(List<int> poly, int scalar) {
    if (scalar == 0) return [0];
    if (scalar == 1) return List<int>.from(poly);
    return List<int>.generate(poly.length, (i) => multiply(poly[i], scalar));
  }

  /// Generates the Reed-Solomon generator polynomial for [degree] error correction codewords:
  /// $g(x) = \prod_{i=0}^{degree-1} (x - \alpha^i) = \prod_{i=0}^{degree-1} (x + \alpha^i)$
  List<int> generatorPolynomial(int degree) {
    if (degree <= 0) return [1];
    var g = <int>[1];
    for (var i = 0; i < degree; i++) {
      // Multiply g(x) by (x + alpha^i) = [1, exp(i)]
      g = multiplyPoly(g, [1, exp(i)]);
    }
    return g;
  }
}
