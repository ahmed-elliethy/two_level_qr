import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

void main() {
  group('GaloisField256', () {
    final gf = GaloisField256.instance;

    test('add and subtract are XOR', () {
      expect(gf.add(0x55, 0xAA), equals(0xFF));
      expect(gf.subtract(0x55, 0xAA), equals(0xFF));
      expect(gf.add(0x12, 0x12), equals(0));
    });

    test('multiplication and inverse', () {
      expect(gf.multiply(0, 100), equals(0));
      expect(gf.multiply(100, 0), equals(0));
      expect(gf.multiply(1, 42), equals(42));

      for (var a = 1; a < 256; a++) {
        final inv = gf.inverse(a);
        expect(gf.multiply(a, inv), equals(1), reason: 'Inverse of $a failed');
      }
    });

    test('division', () {
      expect(gf.divide(0, 50), equals(0));
      expect(() => gf.divide(50, 0), throwsArgumentError);

      for (var a = 1; a < 256; a++) {
        for (var b = 1; b < 256; b++) {
          final q = gf.divide(a, b);
          expect(gf.multiply(q, b), equals(a));
        }
      }
    });

    test('generator polynomial degree 2 and 4', () {
      // g_2(x) = (x - alpha^0)(x - alpha^1) = (x + 1)(x + 2) = x^2 + (1^2)x + 2 = x^2 + 3x + 2
      final g2 = gf.generatorPolynomial(2);
      expect(g2, equals([1, 3, 2]));

      final g4 = gf.generatorPolynomial(4);
      expect(g4.length, equals(5));
      expect(g4[0], equals(1));
    });
  });
}
