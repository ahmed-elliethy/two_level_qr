import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

void main() {
  group('Keyed Two-Level QR Hidden Message Channel', () {
    test('Roundtrip: hides and recovers a short secret', () {
      const public = 'https://example.com/public-info';
      const hidden = 'SECRET_42';
      const key = 'my-secret-key';

      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );

      expect(enc.hiddenText, equals(hidden));
      expect(enc.hiddenBytes, isNotNull);
      expect(enc.hiddenBytes!.length, equals(2 + hidden.length));

      final dec = TwoLevelQr.decodeWithHiddenMessage(
        enc.matrix,
        key: key,
      );

      expect(dec.public.text, equals(public));
      expect(dec.hiddenText, equals(hidden));
      expect(dec.hiddenBytes, equals(enc.hiddenBytes!.sublist(2)));
    });

    test('Wrong key returns garbage bytes, not the secret', () {
      const public = 'https://example.com/public-info';
      const hidden = 'SECRET_42';
      const key = 'correct-key';

      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );

      final dec = TwoLevelQr.decodeWithHiddenMessage(
        enc.matrix,
        key: 'wrong-key',
      );

      expect(dec.public.text, equals(public));
      expect(dec.hiddenText, isNot(equals(hidden)));
    });

    test('Standard decode still recovers public text despite injected errors', () {
      const public = 'https://example.com/public-info';
      const hidden = 'SECRET_42';
      const key = 'my-secret-key';

      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );

      final normalDec = TwoLevelQr.decode(enc.matrix);
      expect(normalDec.text, equals(public));
      expect(normalDec.errorsCorrected, greaterThan(0));
    });

    test('Different keys produce different error position schedules', () {
      const public = 'https://example.com/public-info';
      const hidden = 'SECRET_42';

      final enc1 = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: 'key-alpha',
        level: ErrorCorrectionLevel.high,
      );

      final enc2 = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: 'key-beta',
        level: ErrorCorrectionLevel.high,
      );

      expect(enc1.matrix, isNot(equals(enc2.matrix)));
    });

    test('Hides and recovers a longer UTF-8 secret', () {
      const public = 'https://example.com/two-level-qr';
      const hidden = 'The quick brown fox jumps over 13 lazy dogs. 🦊🐕';
      const key = 'utf8-key-123';

      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
        explicitVersion: 10,
      );

      expect(enc.version.number, equals(10));

      final dec = TwoLevelQr.decodeWithHiddenMessage(
        enc.matrix,
        key: key,
      );

      expect(dec.public.text, equals(public));
      expect(dec.hiddenText, equals(hidden));
    });

    test('Matrix noise plus hidden errors are both corrected', () {
      const public = 'https://example.com/public-info';
      const hidden = 'SECRET_42';
      const key = 'noise-key';

      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        level: ErrorCorrectionLevel.high,
      );

      final noisyMatrix = enc.matrix.clone();
      // Flip a few random-ish data modules to simulate scanner noise.
      noisyMatrix.toggle(10, 10);
      noisyMatrix.toggle(12, 14);
      noisyMatrix.toggle(14, 18);

      final dec = TwoLevelQr.decodeWithHiddenMessage(
        noisyMatrix,
        key: key,
      );

      expect(dec.public.text, equals(public));
      expect(dec.hiddenText, equals(hidden));
      expect(dec.public.errorsCorrected, greaterThan(0));
    });

    test('Throws when hidden message exceeds fixed version capacity', () {
      const public = 'https://example.com';
      const key = 'capacity-key';

      // Version 1-H has very small data capacity; a 100-byte secret cannot fit.
      expect(
        () => TwoLevelQr.encodeWithHiddenMessage(
          publicText: public,
          hiddenText: 'A' * 100,
          key: key,
          level: ErrorCorrectionLevel.high,
          explicitVersion: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws meaningful exception when hidden message exceeds max version 40 capacity', () {
      const public = 'https://example.com';
      const key = 'capacity-key';

      expect(
        () => TwoLevelQr.encodeWithHiddenMessage(
          publicText: public,
          hiddenText: 'A' * 2000,
          key: key,
          level: ErrorCorrectionLevel.high,
        ),
        throwsA(
          isA<HiddenMessageCapacityException>().having(
            (e) => e.hiddenPayloadBytes,
            'hiddenPayloadBytes',
            2000,
          ),
        ),
      );
    });

    test('Configurable ratio changes usable capacity', () {
      const public = 'https://example.com/public-info';
      const hidden = 'SECRET_42';
      const key = 'ratio-key';

      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: public,
        hiddenText: hidden,
        key: key,
        ratio: 0.8,
        level: ErrorCorrectionLevel.high,
      );

      final dec = TwoLevelQr.decodeWithHiddenMessage(
        enc.matrix,
        key: key,
        ratio: 0.8,
      );

      expect(dec.hiddenText, equals(hidden));

      // A mismatched ratio on decode schedules a different number of positions,
      // so the hidden text should not decode correctly.
      final decWrongRatio = TwoLevelQr.decodeWithHiddenMessage(
        enc.matrix,
        key: key,
        ratio: 0.5,
      );
      expect(decWrongRatio.hiddenText, isNot(equals(hidden)));
    });
  });
}
