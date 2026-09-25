import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

void main() {
  group('ReedSolomonCodec', () {
    final rs = ReedSolomonCodec();

    test('generates known ECC codewords (v1-M example)', () {
      // 16 data codewords for "HELLO WORLD" in v1-M
      final data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17];
      final ecc = rs.generateEcc(data: data, eccCodewordsCount: 10);
      expect(ecc.length, equals(10));
      expect(ecc.bytes, equals([196, 35, 39, 119, 235, 215, 231, 226, 93, 23]));
    });

    test('corrects 0 errors (clean codeword)', () {
      final data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17];
      final ecc = rs.generateEcc(data: data, eccCodewordsCount: 10);
      final received = [...data, ...ecc.bytes];

      final result = rs.correctBlock(
        received: received,
        dataCodewordsCount: data.length,
        eccCodewordsCount: 10,
      );

      expect(result.errorsCorrected, equals(0));
      expect(result.data, equals(data));
    });

    test('corrects up to t errors (t = 5 for 10 ECC codewords)', () {
      final data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
      final ecc = rs.generateEcc(data: data, eccCodewordsCount: 10);
      final received = [...data, ...ecc.bytes];

      // Corrupt 5 arbitrary positions (2 data, 3 ECC)
      received[0] ^= 0x55;
      received[5] ^= 0xAA;
      received[16] ^= 0x12;
      received[20] ^= 0x34;
      received[25] ^= 0xFF;

      final result = rs.correctBlock(
        received: received,
        dataCodewordsCount: data.length,
        eccCodewordsCount: 10,
      );

      expect(result.errorsCorrected, equals(5));
      expect(result.data, equals(data));
    });

    test('throws ReedSolomonException when errors exceed t (6 > 5)', () {
      final data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
      final ecc = rs.generateEcc(data: data, eccCodewordsCount: 10);
      final received = [...data, ...ecc.bytes];

      // Corrupt 6 positions
      for (var i = 0; i < 6; i++) {
        received[i * 4] ^= 0xFF;
      }

      expect(
        () => rs.correctBlock(
          received: received,
          dataCodewordsCount: data.length,
          eccCodewordsCount: 10,
        ),
        throwsA(isA<ReedSolomonException>()),
      );
    });
  });
}
