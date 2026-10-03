import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../domain/hidden_cipher.dart';
import 'passphrase_kdf.dart';

/// Thrown by [AesSiv.decrypt] when the synthetic IV does not authenticate.
class AesSivAuthenticationException implements Exception {
  const AesSivAuthenticationException();

  @override
  String toString() => 'AesSivAuthenticationException: authentication failed';
}

/// AES-SIV authenticated encryption (RFC 5297), composed from pointycastle's
/// AES, AES-CMAC and AES-CTR.
///
/// Only the SIV mode logic (S2V, `dbl`, `xorend`) lives here; the block
/// cipher, MAC and counter mode are pointycastle's. Output layout is
/// `V (16 bytes) || C`.
class AesSiv {
  AesSiv._();

  static const int blockSize = 16;

  /// Encrypts [plaintext] under [key] (32, 48 or 64 bytes: the first half is
  /// the CMAC key, the second half the CTR key), authenticating every entry
  /// of [associatedData] as a separate S2V component.
  static Uint8List encrypt({
    required Uint8List key,
    required List<Uint8List> associatedData,
    required Uint8List plaintext,
  }) {
    final (k1, k2) = _splitKey(key, associatedData);
    final v = _s2v(k1, associatedData, plaintext);
    final c = _ctr(k2, v, plaintext);
    return Uint8List(blockSize + c.length)
      ..setRange(0, blockSize, v)
      ..setRange(blockSize, blockSize + c.length, c);
  }

  /// Decrypts `V || C`. Throws [AesSivAuthenticationException] if the input
  /// is shorter than 16 bytes or does not authenticate.
  static Uint8List decrypt({
    required Uint8List key,
    required List<Uint8List> associatedData,
    required Uint8List ciphertext,
  }) {
    final (k1, k2) = _splitKey(key, associatedData);
    if (ciphertext.length < blockSize) {
      throw const AesSivAuthenticationException();
    }
    final v = Uint8List.sublistView(ciphertext, 0, blockSize);
    final c = Uint8List.sublistView(ciphertext, blockSize);
    final p = _ctr(k2, v, c);
    final t = _s2v(k1, associatedData, p);
    if (!_constantTimeEquals(t, v)) {
      throw const AesSivAuthenticationException();
    }
    return p;
  }

  static (Uint8List, Uint8List) _splitKey(
    Uint8List key,
    List<Uint8List> associatedData,
  ) {
    if (key.length != 32 && key.length != 48 && key.length != 64) {
      throw ArgumentError.value(
          key.length, 'key.length', 'AES-SIV keys must be 32, 48 or 64 bytes');
    }
    // RFC 5297 §7: at most 126 associated-data components.
    if (associatedData.length > 126) {
      throw ArgumentError('AES-SIV supports at most 126 AD components');
    }
    final half = key.length ~/ 2;
    return (
      Uint8List.sublistView(key, 0, half),
      Uint8List.sublistView(key, half),
    );
  }

  /// S2V (RFC 5297 §2.4) over `associatedData..., plaintext`.
  static Uint8List _s2v(
    Uint8List k1,
    List<Uint8List> associatedData,
    Uint8List plaintext,
  ) {
    // See [_KeyedAes] for why the real key is not passed to CMac.init.
    final mac = CMac(_KeyedAes(k1), 128)
      ..init(KeyParameter(Uint8List(AesSiv.blockSize)));
    Uint8List cmac(Uint8List data) {
      mac.reset();
      mac.update(data, 0, data.length);
      final out = Uint8List(blockSize);
      mac.doFinal(out, 0);
      return out;
    }

    var d = cmac(Uint8List(blockSize));
    for (final ad in associatedData) {
      d = _xor(_dbl(d), cmac(ad));
    }

    final Uint8List t;
    if (plaintext.length >= blockSize) {
      // xorend: XOR D into the last 16 bytes of the plaintext.
      t = Uint8List.fromList(plaintext);
      final off = t.length - blockSize;
      for (var i = 0; i < blockSize; i++) {
        t[off + i] ^= d[i];
      }
    } else {
      // pad with 10*, then XOR with dbl(D).
      final padded = Uint8List(blockSize)
        ..setRange(0, plaintext.length, plaintext);
      padded[plaintext.length] = 0x80;
      t = _xor(_dbl(d), padded);
    }
    return cmac(t);
  }

  /// AES-CTR with the counter Q = V with bits 31 and 63 cleared (§2.6).
  static Uint8List _ctr(Uint8List k2, Uint8List v, Uint8List input) {
    final q = Uint8List.fromList(v);
    q[8] &= 0x7F;
    q[12] &= 0x7F;
    final ctr = CTRStreamCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(k2), q));
    return ctr.process(input);
  }

  /// Doubling in GF(2^128) (§2.3).
  static Uint8List _dbl(Uint8List s) {
    final out = Uint8List(blockSize);
    for (var i = 0; i < blockSize - 1; i++) {
      out[i] = ((s[i] << 1) | (s[i + 1] >> 7)) & 0xFF;
    }
    final carryMask = -(s[0] >> 7) & 0x87;
    out[blockSize - 1] = ((s[blockSize - 1] << 1) & 0xFF) ^ carryMask;
    return out;
  }

  static Uint8List _xor(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = a[i] ^ b[i];
    }
    return out;
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// AES with a fixed key, ignoring the key in the parameters it is given.
///
/// Workaround for pointycastle 4.0.0: `CMac.init` builds its all-zero CBC IV
/// with the *key* length instead of the block size, so AES-192/256-CMAC
/// throws "Initialization vector must be the same length as block size".
/// [AesSiv] therefore initializes CMac with a dummy 16-byte key and this
/// adapter feeds the real key to [AESEngine]. The CMAC algorithm itself is
/// still pointycastle's; the 384/512-bit Wycheproof vectors cover this path.
class _KeyedAes implements BlockCipher {
  _KeyedAes(this._key);

  final Uint8List _key;
  final AESEngine _engine = AESEngine();

  @override
  String get algorithmName => _engine.algorithmName;

  @override
  int get blockSize => _engine.blockSize;

  @override
  void init(bool forEncryption, CipherParameters? params) =>
      _engine.init(forEncryption, KeyParameter(_key));

  @override
  int processBlock(Uint8List inp, int inpOff, Uint8List out, int outOff) =>
      _engine.processBlock(inp, inpOff, out, outOff);

  @override
  Uint8List process(Uint8List data) {
    final out = Uint8List(blockSize);
    processBlock(data, 0, out, 0);
    return out;
  }

  @override
  void reset() => _engine.reset();
}

/// Built-in AES-SIV cipher (scheme ID `0x01`): AES-SIV-CMAC-512 (AES-256)
/// with a 64-byte key derived from the passphrase by [PassphraseKdf].
///
/// Overhead is 16 bytes (the synthetic IV). Encryption is deterministic: the
/// same passphrase, public text and hidden text always give the same bytes.
class AesSivCipher extends HiddenMessageCipher {
  const AesSivCipher({this.iterations = PassphraseKdf.defaultIterations});

  static const int id = 0x01;

  /// PBKDF2 iteration count. Must be the same when encoding and decoding.
  final int iterations;

  @override
  int get schemeId => id;

  @override
  String get name => 'AES-SIV-CMAC-512';

  @override
  int get overhead => AesSiv.blockSize;

  @override
  Uint8List encrypt({
    required String encryptionPassphrase,
    required Uint8List plaintext,
    required Uint8List associatedData,
  }) {
    return AesSiv.encrypt(
      key: _key(encryptionPassphrase, associatedData),
      associatedData: [associatedData],
      plaintext: plaintext,
    );
  }

  @override
  Uint8List decrypt({
    required String encryptionPassphrase,
    required Uint8List ciphertext,
    required Uint8List associatedData,
  }) {
    try {
      return AesSiv.decrypt(
        key: _key(encryptionPassphrase, associatedData),
        associatedData: [associatedData],
        ciphertext: ciphertext,
      );
    } on AesSivAuthenticationException {
      throw const HiddenMessageDecryptionException(
          'AES-SIV authentication failed (wrong passphrase or tampered data).');
    }
  }

  Uint8List _key(String encryptionPassphrase, Uint8List associatedData) =>
      PassphraseKdf.derive(
        encryptionPassphrase: encryptionPassphrase,
        associatedData: associatedData,
        length: 64,
        iterations: iterations,
      );
}
