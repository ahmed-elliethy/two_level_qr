@TestOn('vm') // pointycastle's Poly1305 needs 64-bit integers.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

import 'hex.dart';

void main() {
  group('ChaCha20-Poly1305 (pointycastle) RFC 8439 §2.8.2', () {
    final plaintext = Uint8List.fromList(utf8.encode(
        "Ladies and Gentlemen of the class of '99: If I could offer you only "
        'one tip for the future, sunscreen would be it.'));
    final aad = hex('50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7');
    final key = hex('80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f '
        '90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f');
    final nonce = hex('07 00 00 00 40 41 42 43 44 45 46 47');
    final ciphertext = hex(
        'd3 1a 8d 34 64 8e 60 db 7b 86 af bc 53 ef 7e c2 '
        'a4 ad ed 51 29 6e 08 fe a9 e2 b5 a7 36 ee 62 d6 '
        '3d be a4 5e 8c a9 67 12 82 fa fb 69 da 92 72 8b '
        '1a 71 de 0a 9e 06 0b 29 05 d6 a5 b6 7e cd 3b 36 '
        '92 dd bd 7f 2d 77 8b 8c 98 03 ae e3 28 09 1b 58 '
        'fa b3 24 e4 fa d6 75 94 55 85 80 8b 48 31 d7 bc '
        '3f f4 de f0 8e 4b 7a 9d e5 76 d2 65 86 ce c6 4b '
        '61 16');
    final tag = hex('1a:e1:0b:59:4f:09:e2:6a:7e:90:2e:cb:d0:60:06:91');

    test('seal produces ciphertext || tag', () {
      final sealed = ChaCha20Poly1305Cipher.seal(
          key: key, nonce: nonce, associatedData: aad, plaintext: plaintext);
      expect(sealed, equals([...ciphertext, ...tag]));
    });

    test('open recovers the plaintext and rejects a bad tag', () {
      final sealed = Uint8List.fromList([...ciphertext, ...tag]);
      expect(
          ChaCha20Poly1305Cipher.open(
              key: key, nonce: nonce, associatedData: aad, sealed: sealed),
          equals(plaintext));
      final bad = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1;
      expect(
          () => ChaCha20Poly1305Cipher.open(
              key: key, nonce: nonce, associatedData: aad, sealed: bad),
          throwsA(anything));
    });
  });

  group('ChaCha20Poly1305Cipher', () {
    final cipher = ChaCha20Poly1305Cipher(iterations: 1000, random: Random(7));
    final ad = Uint8List.fromList(utf8.encode('associated'));
    final pt = Uint8List.fromList(utf8.encode('secret ✓'));

    test('layout is nonce(12) || ct || tag(16)', () {
      final out = cipher.encrypt(
          encryptionPassphrase: 'pw', plaintext: pt, associatedData: ad);
      expect(out.length, pt.length + cipher.overhead);
      expect(cipher.overhead, 28);
      expect(
          cipher.decrypt(
              encryptionPassphrase: 'pw', ciphertext: out, associatedData: ad),
          equals(pt));
    });

    test('fresh nonce per encryption', () {
      final a = cipher.encrypt(
          encryptionPassphrase: 'pw', plaintext: pt, associatedData: ad);
      final b = cipher.encrypt(
          encryptionPassphrase: 'pw', plaintext: pt, associatedData: ad);
      expect(a.sublist(0, 12), isNot(equals(b.sublist(0, 12))));
    });

    test('wrong passphrase, tampering and short input throw', () {
      final out = cipher.encrypt(
          encryptionPassphrase: 'pw', plaintext: pt, associatedData: ad);
      final matcher = throwsA(isA<HiddenMessageDecryptionException>());
      expect(
          () => cipher.decrypt(
              encryptionPassphrase: 'PW', ciphertext: out, associatedData: ad),
          matcher);
      for (var i = 0; i < out.length; i++) {
        final bad = Uint8List.fromList(out)..[i] ^= 0x40;
        expect(
            () => cipher.decrypt(
                encryptionPassphrase: 'pw',
                ciphertext: bad,
                associatedData: ad),
            matcher);
      }
      expect(
          () => cipher.decrypt(
              encryptionPassphrase: 'pw',
              ciphertext: Uint8List(27),
              associatedData: ad),
          matcher);
    });
  });
}
