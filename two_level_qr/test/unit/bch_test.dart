import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

void main() {
  group('BchCodec', () {
    test('Format Info: encodes and decodes all 32 combinations without error', () {
      final codec = FormatInfoCodec();
      for (final level in ErrorCorrectionLevel.values) {
        for (final mask in MaskPattern.values) {
          final encoded = codec.encode(level, mask);
          final decoded = codec.decode(encoded.bits15);
          expect(decoded.level, equals(level));
          expect(decoded.maskPattern, equals(mask));
        }
      }
    });

    test('Format Info: corrects up to 3 bit errors', () {
      final codec = FormatInfoCodec();
      final original = codec.encode(ErrorCorrectionLevel.high, MaskPattern.pattern4);

      // Flip 3 bits
      final corruptedBits = original.bits15 ^ (1 << 0) ^ (1 << 5) ^ (1 << 12);
      final decoded = codec.decode(corruptedBits);

      expect(decoded.level, equals(ErrorCorrectionLevel.high));
      expect(decoded.maskPattern, equals(MaskPattern.pattern4));
    });

    test('Version Info: encodes and decodes versions 7..40', () {
      final codec = VersionInfoCodec();
      for (var v = 7; v <= 40; v++) {
        final version = QrVersion(v);
        final encoded = codec.encode(version);
        final decoded = codec.decode(encoded.bits18);
        expect(decoded.version.number, equals(v));
      }
    });

    test('Version Info: corrects up to 3 bit errors', () {
      final codec = VersionInfoCodec();
      final version = QrVersion(10);
      final encoded = codec.encode(version);

      final corrupted = encoded.bits18 ^ (1 << 2) ^ (1 << 8) ^ (1 << 15);
      final decoded = codec.decode(corrupted);

      expect(decoded.version.number, equals(10));
    });
  });
}
