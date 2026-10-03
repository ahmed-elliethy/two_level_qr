import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

import 'hex.dart';

Uint8List _ascii(String s) => Uint8List.fromList(ascii.encode(s));

void main() {
  group('PBKDF2-HMAC-SHA256 RFC 7914 §11 vectors', () {
    test('P="passwd", S="salt", c=1, dkLen=64', () {
      expect(
        PassphraseKdf.pbkdf2HmacSha256(
            password: _ascii('passwd'),
            salt: _ascii('salt'),
            iterations: 1,
            length: 64),
        equals(hex('55 ac 04 6e 56 e3 08 9f ec 16 91 c2 25 44 b6 05 '
            'f9 41 85 21 6d de 04 65 e6 8b 9d 57 c2 0d ac bc '
            '49 ca 9c cc f1 79 b6 45 99 16 64 b3 9d 77 ef 31 '
            '7c 71 b8 45 b1 e3 0b d5 09 11 20 41 d3 a1 97 83')),
      );
    });

    test('P="Password", S="NaCl", c=80000, dkLen=64', () {
      expect(
        PassphraseKdf.pbkdf2HmacSha256(
            password: _ascii('Password'),
            salt: _ascii('NaCl'),
            iterations: 80000,
            length: 64),
        equals(hex('4d dc d8 f6 0b 98 be 21 83 0c ee 5e f2 27 01 f9 '
            '64 1a 44 18 d0 4c 04 14 ae ff 08 87 6b 34 ab 56 '
            'a1 d4 25 a1 22 58 33 54 9a db 84 1b 51 c9 b3 17 '
            '6a 27 2b de bb a1 d0 78 47 8f 62 b3 97 f3 3c 8d')),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('PassphraseKdf.derive', () {
    final ad = Uint8List.fromList(utf8.encode('ad-1'));

    test('is deterministic and salted by associated data', () {
      Uint8List d(String p, Uint8List a) => PassphraseKdf.derive(
          encryptionPassphrase: p, associatedData: a, length: 32, iterations: 10);
      expect(d('pw', ad), equals(d('pw', ad)));
      expect(d('pw', ad), isNot(equals(d('pw2', ad))));
      expect(d('pw', ad),
          isNot(equals(d('pw', Uint8List.fromList(utf8.encode('ad-2'))))));
    });

    test('rejects non-positive iteration counts', () {
      expect(
          () => PassphraseKdf.derive(
              encryptionPassphrase: 'pw',
              associatedData: ad,
              length: 32,
              iterations: 0),
          throwsArgumentError);
    });
  });
}
