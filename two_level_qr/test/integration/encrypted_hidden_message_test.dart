import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:two_level_qr/src/usecases/hidden_envelope.dart';
import 'package:two_level_qr/two_level_qr.dart';

const _public = 'https://example.com/public-info';
const _positionKey = 'position-key';
const _passphrase = 'correct horse battery staple';

/// Built-in ciphers runnable on the current platform.
final List<HiddenMessageCipher> _builtIns = [
  const AesSivCipher(),
  if (ChaCha20Poly1305Cipher.isSupported) ChaCha20Poly1305Cipher(),
];

final _cryptoError = throwsA(isA<HiddenMessageCryptoException>());

EncodeResult _encode(
  String hidden, {
  HiddenMessageCipher? cipher,
  String publicText = _public,
  String positionKey = _positionKey,
  String passphrase = _passphrase,
  double ratio = 0.8,
  ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
  int? explicitVersion,
}) =>
    TwoLevelQr.encodeWithEncryptedHiddenMessage(
      publicText: publicText,
      hiddenText: hidden,
      positionKey: positionKey,
      encryptionPassphrase: passphrase,
      cipher: cipher,
      ratio: ratio,
      level: level,
      explicitVersion: explicitVersion,
    );

EncryptedHiddenDecodeResult _decode(
  QrMatrix matrix, {
  String positionKey = _positionKey,
  String passphrase = _passphrase,
  double ratio = 0.8,
  List<HiddenMessageCipher>? ciphers,
}) =>
    TwoLevelQr.decodeWithEncryptedHiddenMessage(
      matrix,
      positionKey: positionKey,
      encryptionPassphrase: passphrase,
      ratio: ratio,
      ciphers: ciphers,
    );

/// Builds a QR whose hidden channel carries `[len] || payload` verbatim.
EncodeResult _rawChannel(List<int> payload, {String publicText = _public}) =>
    EncodeHiddenQr().executeWithPayload(
      publicText: publicText,
      hiddenText: '',
      payload: payload,
      options: const HiddenEncodeOptions(key: _positionKey),
    );

/// A deliberately simple custom cipher used to test pluggability. NOT secure.
class _XorTagCipher extends HiddenMessageCipher {
  const _XorTagCipher({this.schemeId = 0x80});

  @override
  final int schemeId;

  @override
  String get name => 'XOR-TAG-TEST';

  @override
  int get overhead => 4;

  List<int> _stream(String pass, Uint8List ad, int n) {
    final seed = [...utf8.encode(pass), ...ad];
    var h = 0x12345;
    for (final b in seed) {
      h = (h * 31 + b) & 0x3FFFFFFF;
    }
    final rnd = Random(h);
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }

  @override
  Uint8List encrypt({
    required String encryptionPassphrase,
    required Uint8List plaintext,
    required Uint8List associatedData,
  }) {
    final ks =
        _stream(encryptionPassphrase, associatedData, plaintext.length + 4);
    final out = <int>[
      for (var i = 0; i < plaintext.length; i++) plaintext[i] ^ ks[i],
    ];
    var sum = 0;
    for (final b in plaintext) {
      sum = (sum * 7 + b) & 0xFFFFFFFF;
    }
    for (var i = 0; i < 4; i++) {
      out.add(((sum >> (8 * i)) & 0xFF) ^ ks[plaintext.length + i]);
    }
    return Uint8List.fromList(out);
  }

  @override
  Uint8List decrypt({
    required String encryptionPassphrase,
    required Uint8List ciphertext,
    required Uint8List associatedData,
  }) {
    final n = ciphertext.length - 4;
    final ks = _stream(encryptionPassphrase, associatedData, ciphertext.length);
    final pt = Uint8List.fromList([for (var i = 0; i < n; i++) ciphertext[i] ^ ks[i]]);
    final again = encrypt(
        encryptionPassphrase: encryptionPassphrase,
        plaintext: pt,
        associatedData: associatedData);
    for (var i = 0; i < ciphertext.length; i++) {
      if (again[i] != ciphertext[i]) {
        throw const HiddenMessageDecryptionException('tag mismatch');
      }
    }
    return pt;
  }
}

/// Lies about its overhead.
class _BadOverheadCipher extends _XorTagCipher {
  const _BadOverheadCipher() : super(schemeId: 0x81);

  @override
  int get overhead => 2;
}

void main() {
  group('Encrypted hidden message round trips', () {
    for (final cipher in _builtIns) {
      group(cipher.name, () {
        for (final hidden in [
          'meet at 9pm',
          'Ünïcödé 🔑🚀 مرحبا 你好世界',
          '',
        ]) {
          test('round-trips "${hidden.isEmpty ? '<empty>' : hidden}"', () {
            final enc = _encode(hidden, cipher: cipher);
            final utf8Len = utf8.encode(hidden).length;
            expect(enc.hiddenText, hidden);
            expect(enc.hiddenCipherSchemeId, cipher.schemeId);
            expect(enc.hiddenBytes!.length, 3 + cipher.overhead + utf8Len);
            expect(enc.hiddenBytes![2], cipher.schemeId);

            final dec = _decode(enc.matrix);
            expect(dec.public.text, _public);
            expect(dec.hiddenText, hidden);
            expect(dec.hiddenBytes, utf8.encode(hidden));
            expect(dec.schemeId, cipher.schemeId);
            expect(dec.cipherName, cipher.name);
          });
        }

        test('ciphertext bytes do not reveal the plaintext', () {
          const hidden = 'AAAAAAAAAAAAAAAAAAAA';
          final enc = _encode(hidden, cipher: cipher);
          final body = enc.hiddenBytes!.sublist(3);
          expect(body.where((b) => b == 0x41).length, lessThan(5));
        });
      });
    }

    test('AES-SIV is the default cipher', () {
      final enc = _encode('default');
      expect(enc.hiddenCipherSchemeId, AesSivCipher.id);
    });
  });

  group('Failures never fall back to plaintext', () {
    for (final cipher in _builtIns) {
      group(cipher.name, () {
        late EncodeResult enc;
        setUpAll(() => enc = _encode('top secret', cipher: cipher));

        test('wrong encryption passphrase', () {
          expect(() => _decode(enc.matrix, passphrase: 'wrong'),
              throwsA(isA<HiddenMessageDecryptionException>()));
        });

        test('wrong position key', () {
          expect(() => _decode(enc.matrix, positionKey: 'other-key'),
              _cryptoError);
        });

        test('wrong ratio', () {
          for (final r in [0.5, 1.0]) {
            expect(() => _decode(enc.matrix, ratio: r), _cryptoError);
          }
        });

        test('wrong KDF iteration count', () {
          expect(
            () => TwoLevelQr.decodeWithEncryptedHiddenMessage(enc.matrix,
                positionKey: _positionKey,
                encryptionPassphrase: _passphrase,
                kdfIterations: PassphraseKdf.defaultIterations + 1),
            throwsA(isA<HiddenMessageDecryptionException>()),
          );
        });

        test('payload spliced onto another public text', () {
          final spliced = _rawChannel(enc.hiddenBytes!.sublist(2),
              publicText: 'https://evil.example');
          expect(() => _decode(spliced.matrix),
              throwsA(isA<HiddenMessageDecryptionException>()));
        });
      });
    }

    test('plaintext two-level QR is rejected by the encrypted decoder', () {
      for (final hidden in ['SECRET_42', '\u0001abc', '\u0002xyz']) {
        final plain = TwoLevelQr.encodeWithHiddenMessage(
            publicText: _public, hiddenText: hidden, key: _positionKey);
        expect(() => _decode(plain.matrix), _cryptoError, reason: hidden);
      }
    });

    test('normal QR without hidden data is rejected', () {
      final qr = TwoLevelQr.encode(_public, level: ErrorCorrectionLevel.high);
      expect(() => _decode(qr.matrix), _cryptoError);
    });

    test('random noise either round-trips exactly or throws', () {
      final rnd = Random(42);
      var ok = 0;
      var rejected = 0;
      for (final cipher in _builtIns) {
        final enc = _encode('integrity matters', cipher: cipher);
        final registry =
            const MatrixRenderer().createBaseMatrix(enc.version).registry;
        for (var trial = 0; trial < 40; trial++) {
          final noisy = enc.matrix.clone();
          for (var f = 0; f < 2; f++) {
            int x, y;
            do {
              x = rnd.nextInt(noisy.size);
              y = rnd.nextInt(noisy.size);
            } while (registry.isReserved(x, y));
            noisy.toggle(x, y);
          }
          try {
            final dec = _decode(noisy);
            expect(dec.hiddenText, 'integrity matters');
            expect(dec.public.text, _public);
            ok++;
          } on HiddenMessageCryptoException {
            rejected++;
          }
        }
      }
      expect(ok, greaterThan(0));
      expect(ok + rejected, 40 * _builtIns.length);
    });
  });

  group('Malformed envelopes', () {
    final registry = HiddenEnvelope.registry(_builtIns);

    test('channel too short', () {
      expect(() => HiddenEnvelope.parse([0, 1], registry),
          throwsA(isA<HiddenMessageFormatException>()));
    });

    test('zero length', () {
      expect(() => HiddenEnvelope.parse([0, 0, 1, 2, 3], registry),
          throwsA(isA<HiddenMessageFormatException>()));
      expect(() => _decode(_rawChannel([]).matrix),
          throwsA(isA<HiddenMessageFormatException>()));
    });

    test('length beyond the channel', () {
      final channel = [0x01, 0x00, AesSivCipher.id, ...List.filled(40, 0)];
      expect(() => HiddenEnvelope.parse(channel, registry),
          throwsA(isA<HiddenMessageFormatException>()));
      final overBy1 = [0, 42, AesSivCipher.id, ...List.filled(40, 0)];
      expect(() => HiddenEnvelope.parse(overBy1, registry),
          throwsA(isA<HiddenMessageFormatException>()));
    });

    test('payload shorter than cipher overhead', () {
      final short = _rawChannel([AesSivCipher.id, ...List.filled(15, 7)]);
      expect(() => _decode(short.matrix),
          throwsA(isA<HiddenMessageFormatException>()));
      final enough = _rawChannel([AesSivCipher.id, ...List.filled(16, 7)]);
      expect(() => _decode(enough.matrix),
          throwsA(isA<HiddenMessageDecryptionException>()));
    });

    test('unknown or invalid scheme IDs', () {
      for (final id in [0x00, 0x03, 0x7F, 0x90, 0xFF]) {
        final qr = _rawChannel([id, ...List.filled(30, 1)]);
        expect(
          () => _decode(qr.matrix),
          throwsA(isA<UnsupportedHiddenCipherException>()
              .having((e) => e.schemeId, 'schemeId', id)),
        );
      }
    });

    test('cipher missing from the receiver registry', () {
      final enc = _encode('x', cipher: const AesSivCipher());
      expect(
        () => _decode(enc.matrix, ciphers: [const _XorTagCipher()]),
        throwsA(isA<UnsupportedHiddenCipherException>()),
      );
    });
  });

  group('Capacity and ratio', () {
    for (final cipher in _builtIns) {
      group(cipher.name, () {
        test('hiddenMessageCapacity = plaintext capacity - (1 + overhead)', () {
          for (final level in ErrorCorrectionLevel.values) {
            for (final v in [1, 3, 10, 40]) {
              final plain = TwoLevelQr.hiddenMessageCapacity(
                  version: v, level: level);
              final enc = TwoLevelQr.hiddenMessageCapacity(
                  version: v, level: level, cipher: cipher);
              expect(enc, max(0, plain - 1 - cipher.overhead),
                  reason: 'v$v-${level.label}');
            }
          }
        });

        test('exact capacity fits at an explicit version, one more byte fails',
            () {
          for (final ratio in [0.5, 0.8, 1.0]) {
            const v = 10;
            final cap = TwoLevelQr.hiddenMessageCapacity(
                version: v,
                level: ErrorCorrectionLevel.high,
                ratio: ratio,
                cipher: cipher);
            expect(cap, greaterThan(0));
            final fits =
                _encode('a' * cap, cipher: cipher, ratio: ratio, explicitVersion: v);
            expect(fits.version.number, v);
            expect(_decode(fits.matrix, ratio: ratio).hiddenText, 'a' * cap);
            expect(
              () => _encode('a' * (cap + 1),
                  cipher: cipher, ratio: ratio, explicitVersion: v),
              throwsA(isA<ArgumentError>().having(
                  (e) => '${e.message}', 'message', contains('encryption overhead'))),
            );
          }
        });

        test('v40 overflow reports the encryption overhead', () {
          final cap = TwoLevelQr.hiddenMessageCapacity(
              version: 40, level: ErrorCorrectionLevel.high, cipher: cipher);
          final len = cap + 1;
          expect(
            () => _encode('z' * len, cipher: cipher),
            throwsA(isA<HiddenMessageCapacityException>()
                .having((e) => e.hiddenPayloadBytes, 'payload', len)
                .having((e) => e.overheadBytes, 'overhead', 1 + cipher.overhead)
                .having((e) => e.totalHiddenBytes, 'total',
                    len + 3 + cipher.overhead)),
          );
        });

        test('automatic version increase picks the smallest fitting version',
            () {
          final publicMin = TwoLevelQr.encode(_public,
                  level: ErrorCorrectionLevel.high)
              .version
              .number;
          var previous = 0;
          for (final len in [0, 5, 20, 60, 150, 400]) {
            final hidden = 'h' * len;
            final enc = _encode(hidden, cipher: cipher);
            final v = enc.version.number;
            expect(v, greaterThanOrEqualTo(previous));
            previous = v;
            expect(
                TwoLevelQr.hiddenMessageCapacity(
                    version: v, level: ErrorCorrectionLevel.high, cipher: cipher),
                greaterThanOrEqualTo(len));
            if (v > publicMin) {
              // The previous version's channel cannot hold the envelope.
              expect(
                  HiddenEnvelope.channelCapacity(
                      version: v - 1,
                      level: ErrorCorrectionLevel.high,
                      ratio: 0.8),
                  lessThan(len + HiddenEnvelope.framingBytes + cipher.overhead),
                  reason: 'len $len should not fit in v${v - 1}');
            }
            final plain = TwoLevelQr.encodeWithHiddenMessage(
                publicText: _public, hiddenText: hidden, key: _positionKey);
            expect(v, greaterThanOrEqualTo(plain.version.number));
            expect(_decode(enc.matrix).hiddenText, hidden);
          }
          expect(previous, greaterThan(publicMin));
        });

        test('per-block hidden errors never exceed min(t-1, floor(ratio*t))',
            () {
          for (final level in ErrorCorrectionLevel.values) {
            for (final ratio in [0.3, 0.5, 0.8, 1.0]) {
              final enc = _encode('ratio check ✓',
                  cipher: cipher, ratio: ratio, level: level);
              final pub = TwoLevelQr.decode(enc.matrix);
              final raw = const BlockInterleaver().deinterleave(
                  rawCodewords: pub.rawCodewords,
                  version: pub.version,
                  level: pub.level);
              final cor = pub.correctedCodewords.blocks;
              var total = 0;
              for (var b = 0; b < raw.length; b++) {
                final t = raw[b].eccCodewords.length ~/ 2;
                final budget = t <= 1 ? 0 : min(t - 1, (t * ratio).floor());
                var errors = 0;
                for (var i = 0; i < raw[b].fullBlock.length; i++) {
                  if (raw[b].fullBlock[i] != cor[b].fullBlock[i]) errors++;
                }
                expect(errors, lessThanOrEqualTo(budget),
                    reason: '${level.label} r$ratio block $b');
                total += errors;
              }
              expect(total, lessThanOrEqualTo(enc.hiddenBytes!.length));
              expect(_decode(enc.matrix, ratio: ratio).hiddenText,
                  'ratio check ✓');
            }
          }
        });
      });
    }

    test('small ratio bumps the version past channels too small for framing',
        () {
      // v1-H at ratio 0.3 holds 2 channel bytes: not even the AES-SIV framing.
      expect(
          TwoLevelQr.hiddenMessageCapacity(
              version: 1,
              level: ErrorCorrectionLevel.high,
              ratio: 0.3,
              cipher: const AesSivCipher()),
          0);
      final enc = _encode('', publicText: 'A', ratio: 0.3);
      expect(enc.version.number, greaterThan(1));
      expect(_decode(enc.matrix, ratio: 0.3).hiddenText, '');
      expect(
        () => _encode('', publicText: 'A', ratio: 0.3, explicitVersion: 1),
        throwsArgumentError,
      );
    });
  });

  group('Argument validation', () {
    test('positionKey and encryptionPassphrase must differ', () {
      expect(() => _encode('x', positionKey: 'same', passphrase: 'same'),
          throwsArgumentError);
    });

    test('empty passphrase and bad ratio are rejected', () {
      expect(() => _encode('x', passphrase: ''), throwsArgumentError);
      expect(() => _encode('x', ratio: 0), throwsArgumentError);
      expect(() => _encode('x', ratio: 1.5), throwsArgumentError);
      final enc = _encode('x');
      expect(() => _decode(enc.matrix, passphrase: ''), throwsArgumentError);
    });

    test('default KDF iteration count is the proof-of-concept value', () {
      expect(PassphraseKdf.defaultIterations, 1000);
      expect(const AesSivCipher().iterations, 1000);
    });

    test('kdfIterations is honored for encode and decode', () {
      final enc = TwoLevelQr.encodeWithEncryptedHiddenMessage(
          publicText: _public,
          hiddenText: 'slow',
          positionKey: _positionKey,
          encryptionPassphrase: _passphrase,
          kdfIterations: 5000);
      expect(
          TwoLevelQr.decodeWithEncryptedHiddenMessage(enc.matrix,
                  positionKey: _positionKey,
                  encryptionPassphrase: _passphrase,
                  kdfIterations: 5000)
              .hiddenText,
          'slow');
      expect(() => _decode(enc.matrix),
          throwsA(isA<HiddenMessageDecryptionException>()));
    });
  });

  group('Custom ciphers', () {
    const custom = _XorTagCipher();

    test('round-trips when registered', () {
      final enc = _encode('pluggable ✓', cipher: custom);
      expect(enc.hiddenCipherSchemeId, 0x80);
      final dec = _decode(enc.matrix, ciphers: [..._builtIns, custom]);
      expect(dec.hiddenText, 'pluggable ✓');
      expect(dec.cipherName, 'XOR-TAG-TEST');
      expect(() => _decode(enc.matrix, passphrase: 'nope', ciphers: [custom]),
          throwsA(isA<HiddenMessageDecryptionException>()));
    });

    test('is unsupported when the receiver does not register it', () {
      final enc = _encode('pluggable', cipher: custom);
      expect(
        () => _decode(enc.matrix),
        throwsA(isA<UnsupportedHiddenCipherException>()
            .having((e) => e.schemeId, 'schemeId', 0x80)),
      );
    });

    test('reserved or invalid scheme IDs are rejected', () {
      for (final id in [0x00, 0x01, 0x02, 0x7F, 0xFF]) {
        expect(() => _encode('x', cipher: _XorTagCipher(schemeId: id)),
            throwsArgumentError,
            reason: 'id $id');
        final enc = _encode('x');
        expect(() => _decode(enc.matrix, ciphers: [_XorTagCipher(schemeId: id)]),
            throwsArgumentError);
      }
    });

    test('duplicate scheme IDs in the registry are rejected', () {
      final enc = _encode('x');
      expect(
          () => _decode(enc.matrix,
              ciphers: [const AesSivCipher(), const AesSivCipher()]),
          throwsArgumentError);
    });

    test('a cipher that misreports its overhead is caught', () {
      expect(() => _encode('x', cipher: const _BadOverheadCipher()),
          throwsStateError);
    });
  });

  group('Plaintext mode is unchanged', () {
    test('plaintext encodes carry no scheme byte and no cipher ID', () {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
          publicText: _public, hiddenText: 'SECRET', key: _positionKey);
      expect(enc.hiddenCipherSchemeId, isNull);
      expect(enc.hiddenBytes, [0, 6, ...utf8.encode('SECRET')]);
      final dec =
          TwoLevelQr.decodeWithHiddenMessage(enc.matrix, key: _positionKey);
      expect(dec.hiddenText, 'SECRET');
    });

    test('plaintext decoder on an encrypted QR returns no plaintext', () {
      final enc = _encode('very secret');
      final dec =
          TwoLevelQr.decodeWithHiddenMessage(enc.matrix, key: _positionKey);
      expect(dec.hiddenText, isNot(contains('very secret')));
    });
  });

  group('Platform support', () {
    test('ChaCha20-Poly1305 is unavailable on the web', () {
      expect(ChaCha20Poly1305Cipher.isSupported, isFalse);
      expect(
          () => ChaCha20Poly1305Cipher().encrypt(
              encryptionPassphrase: 'p',
              plaintext: Uint8List(1),
              associatedData: Uint8List(0)),
          throwsUnsupportedError);
      expect(HiddenEnvelope.defaultCiphers().map((c) => c.schemeId),
          [AesSivCipher.id]);
    }, testOn: 'js');

    test('both built-ins are available on native platforms', () {
      expect(ChaCha20Poly1305Cipher.isSupported, isTrue);
      expect(HiddenEnvelope.defaultCiphers().map((c) => c.schemeId),
          [AesSivCipher.id, ChaCha20Poly1305Cipher.id]);
    }, testOn: 'vm');
  });
}
