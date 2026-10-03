import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

import '../vectors/wycheproof_aes_siv_cmac.dart';
import 'hex.dart';

void main() {
  group('AesSiv RFC 5297 vectors', () {
    test('A.1 deterministic authenticated encryption', () {
      final key = hex('fffefdfc fbfaf9f8 f7f6f5f4 f3f2f1f0 '
          'f0f1f2f3 f4f5f6f7 f8f9fafb fcfdfeff');
      final ad = [hex('10111213 14151617 18191a1b 1c1d1e1f 20212223 24252627')];
      final pt = hex('11223344 55667788 99aabbcc ddee');
      final expected = hex('85632d07 c6e8f37f 950acd32 0a2ecc93 '
          '40c02b96 90c4dc04 daef7f6a fe5c');

      final ct = AesSiv.encrypt(key: key, associatedData: ad, plaintext: pt);
      expect(ct, equals(expected));
      expect(AesSiv.decrypt(key: key, associatedData: ad, ciphertext: ct),
          equals(pt));
    });

    test('A.2 nonce-based authenticated encryption (3 AD components)', () {
      final key = hex('7f7e7d7c 7b7a7978 77767574 73727170 '
          '40414243 44454647 48494a4b 4c4d4e4f');
      final ad = [
        hex('00112233 44556677 8899aabb ccddeeff '
            'deaddada deaddada ffeeddcc bbaa9988 77665544 33221100'),
        hex('10203040 50607080 90a0'),
        hex('09f91102 9d74e35b d84156c5 635688c0'), // nonce
      ];
      final pt = hex('74686973 20697320 736f6d65 20706c61 '
          '696e7465 78742074 6f20656e 63727970 '
          '74207573 696e6720 5349562d 414553');
      final expected = hex('7bdb6e3b 432667eb 06f4d14b ff2fbd0f '
          'cb900f2f ddbe4043 26601965 c889bf17 '
          'dba77ceb 094fa663 b7a3f748 ba8af829 '
          'ea64ad54 4a272e9c 485b62a3 fd5c0d');

      final ct = AesSiv.encrypt(key: key, associatedData: ad, plaintext: pt);
      expect(ct, equals(expected));
      expect(AesSiv.decrypt(key: key, associatedData: ad, ciphertext: ct),
          equals(pt));
    });
  });

  group('AesSiv Wycheproof aes_siv_cmac_test', () {
    test('all ${wycheproofAesSivCmac.length} vectors', () {
      var valid = 0;
      var invalid = 0;
      for (final (id, keyBits, keyHex, aadHex, msgHex, ctHex, isValid)
          in wycheproofAesSivCmac) {
        final key = hex(keyHex);
        expect(key.length * 8, keyBits, reason: 'tc $id');
        final ad = [hex(aadHex)];
        final msg = hex(msgHex);
        final ct = hex(ctHex);
        if (isValid) {
          valid++;
          expect(AesSiv.encrypt(key: key, associatedData: ad, plaintext: msg),
              equals(ct),
              reason: 'tc $id encrypt');
          expect(AesSiv.decrypt(key: key, associatedData: ad, ciphertext: ct),
              equals(msg),
              reason: 'tc $id decrypt');
        } else {
          invalid++;
          expect(
            () => AesSiv.decrypt(key: key, associatedData: ad, ciphertext: ct),
            throwsA(isA<AesSivAuthenticationException>()),
            reason: 'tc $id must be rejected',
          );
        }
      }
      expect(valid, 118);
      expect(invalid, 324);
    });
  });

  group('AesSiv misuse', () {
    final key = Uint8List.fromList(List.generate(64, (i) => i));
    final ad = [Uint8List.fromList(utf8.encode('ad'))];

    test('every single-bit flip of V||C is rejected', () {
      final ct = AesSiv.encrypt(
          key: key,
          associatedData: ad,
          plaintext: Uint8List.fromList(utf8.encode('hello SIV world!!')));
      for (var bit = 0; bit < ct.length * 8; bit++) {
        final bad = Uint8List.fromList(ct);
        bad[bit ~/ 8] ^= 1 << (bit % 8);
        expect(() => AesSiv.decrypt(key: key, associatedData: ad, ciphertext: bad),
            throwsA(isA<AesSivAuthenticationException>()));
      }
    });

    test('modified associated data is rejected', () {
      final ct = AesSiv.encrypt(
          key: key, associatedData: ad, plaintext: Uint8List.fromList([1, 2]));
      expect(
          () => AesSiv.decrypt(
              key: key,
              associatedData: [Uint8List.fromList(utf8.encode('aD'))],
              ciphertext: ct),
          throwsA(isA<AesSivAuthenticationException>()));
    });

    test('short input and bad key sizes', () {
      expect(
          () => AesSiv.decrypt(
              key: key, associatedData: ad, ciphertext: Uint8List(15)),
          throwsA(isA<AesSivAuthenticationException>()));
      expect(
          () => AesSiv.encrypt(
              key: Uint8List(16), associatedData: ad, plaintext: Uint8List(0)),
          throwsArgumentError);
    });

    test('empty plaintext round-trips', () {
      final ct =
          AesSiv.encrypt(key: key, associatedData: ad, plaintext: Uint8List(0));
      expect(ct.length, 16);
      expect(AesSiv.decrypt(key: key, associatedData: ad, ciphertext: ct),
          isEmpty);
    });
  });
}
