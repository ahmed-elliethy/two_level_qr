import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

void main() {
  group('End-to-End QR Encode & Decode Pipeline', () {
    test('Roundtrip: Numeric payload (Version 1-L)', () {
      const text = '0123456789012345';
      final enc = TwoLevelQr.encode(text, level: ErrorCorrectionLevel.low);

      expect(enc.version.number, equals(1));
      expect(enc.level, equals(ErrorCorrectionLevel.low));
      expect(enc.matrix.size, equals(21));

      final dec = TwoLevelQr.decode(enc.matrix);
      expect(dec.text, equals(text));
      expect(dec.version.number, equals(1));
      expect(dec.level, equals(ErrorCorrectionLevel.low));
      expect(dec.errorsCorrected, equals(0));
    });

    test('Roundtrip: Alphanumeric payload (Version 1-M)', () {
      const text = 'HELLO WORLD';
      final enc = TwoLevelQr.encode(text, level: ErrorCorrectionLevel.medium);

      expect(enc.version.number, equals(1));
      expect(enc.level, equals(ErrorCorrectionLevel.medium));

      final dec = TwoLevelQr.decode(enc.matrix);
      expect(dec.text, equals(text));
      expect(dec.version.number, equals(1));
      expect(dec.level, equals(ErrorCorrectionLevel.medium));
      expect(dec.errorsCorrected, equals(0));
    });

    test('Roundtrip: UTF-8 / URL payload with multi-block (Version 7-H)', () {
      const text = 'https://example.com/two_level_qr_clean_architecture_pipeline_demo_stage_checkpoints_2026';
      final enc = TwoLevelQr.encode(text, level: ErrorCorrectionLevel.high);

      expect(enc.version.number, greaterThanOrEqualTo(7));
      expect(enc.level, equals(ErrorCorrectionLevel.high));

      final dec = TwoLevelQr.decode(enc.matrix);
      expect(dec.text, equals(text));
      expect(dec.version.number, equals(enc.version.number));
      expect(dec.level, equals(ErrorCorrectionLevel.high));
    });

    test('Error Correction: Corrupted matrix modules are corrected successfully', () {
      const text = 'TWO_LEVEL_QR_ERROR_TOLERANCE_TEST';
      final enc = TwoLevelQr.encode(text, level: ErrorCorrectionLevel.high);

      final noisyMatrix = enc.matrix.clone();

      // Introduce isolated corrupted modules in data regions
      noisyMatrix.toggle(10, 10);
      noisyMatrix.toggle(11, 12);
      noisyMatrix.toggle(12, 14);
      noisyMatrix.toggle(13, 16);

      final dec = TwoLevelQr.decode(noisyMatrix);
      expect(dec.text, equals(text));
      expect(dec.errorsCorrected, greaterThan(0));
    });

    test('All pipeline stages are first-class and inspectable', () {
      const text = 'CHECKPOINTS_TEST';
      final enc = TwoLevelQr.encode(text, level: ErrorCorrectionLevel.quartile);

      // Verify all checkpoints exist
      expect(enc.text, equals(text));
      expect(enc.segments.isNotEmpty, isTrue);
      expect(enc.dataCodewords.length, greaterThan(0));
      expect(enc.rsBlocks.isNotEmpty, isTrue);
      expect(enc.finalCodewords.bytes.isNotEmpty, isTrue);
      expect(enc.maskPattern, isNotNull);
      expect(enc.matrix.size, equals(enc.version.size));

      final dec = TwoLevelQr.decode(enc.matrix);
      expect(dec.rawCodewords.length, equals(enc.finalCodewords.bytes.length));
      expect(dec.correctedCodewords.length, equals(enc.dataCodewords.length));
      expect(dec.formatInfo.level, equals(ErrorCorrectionLevel.quartile));
      expect(dec.formatInfo.maskPattern, equals(enc.maskPattern));
    });
  });
}
