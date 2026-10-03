import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../domain/hidden_cipher.dart';
import 'aes_siv.dart';
import 'passphrase_kdf.dart';

/// Built-in ChaCha20-Poly1305 cipher (scheme ID `0x02`, RFC 8439), using
/// pointycastle's AEAD with a 32-byte key derived by [PassphraseKdf].
///
/// Output layout is `nonce (12) || ciphertext || tag (16)`, so the overhead
/// is 28 bytes. A fresh random nonce is drawn for every encryption.
///
/// Native platforms only (Dart VM, Flutter mobile/desktop): pointycastle's
/// Poly1305 needs 64-bit integers, so on the web [encrypt] and [decrypt]
/// throw [UnsupportedError] and the default decoder does not register this
/// cipher. Use [AesSivCipher] for codes that must work in the browser.
class ChaCha20Poly1305Cipher extends HiddenMessageCipher {
  ChaCha20Poly1305Cipher({
    this.iterations = PassphraseKdf.defaultIterations,
    Random? random,
  }) : _random = random;

  static const int id = 0x02;
  static const int nonceLength = 12;
  static const int tagLength = 16;

  /// Whether this platform can run the cipher (false on the web).
  static const bool isSupported = !identical(0, 0.0);

  /// PBKDF2 iteration count. Must be the same when encoding and decoding.
  final int iterations;

  /// Nonce source; `Random.secure()` is created on first use when null.
  final Random? _random;

  @override
  int get schemeId => id;

  @override
  String get name => 'ChaCha20-Poly1305';

  @override
  int get overhead => nonceLength + tagLength;

  @override
  Uint8List encrypt({
    required String encryptionPassphrase,
    required Uint8List plaintext,
    required Uint8List associatedData,
  }) {
    _checkPlatform();
    final random = _random ?? Random.secure();
    final nonce = Uint8List.fromList(
        List<int>.generate(nonceLength, (_) => random.nextInt(256)));
    final sealed = seal(
      key: _key(encryptionPassphrase, associatedData),
      nonce: nonce,
      associatedData: associatedData,
      plaintext: plaintext,
    );
    return Uint8List(nonceLength + sealed.length)
      ..setRange(0, nonceLength, nonce)
      ..setRange(nonceLength, nonceLength + sealed.length, sealed);
  }

  @override
  Uint8List decrypt({
    required String encryptionPassphrase,
    required Uint8List ciphertext,
    required Uint8List associatedData,
  }) {
    _checkPlatform();
    if (ciphertext.length < overhead) {
      throw const HiddenMessageDecryptionException(
          'ChaCha20-Poly1305 payload is shorter than nonce + tag.');
    }
    try {
      return open(
        key: _key(encryptionPassphrase, associatedData),
        nonce: Uint8List.sublistView(ciphertext, 0, nonceLength),
        associatedData: associatedData,
        sealed: Uint8List.sublistView(ciphertext, nonceLength),
      );
    } on ArgumentError {
      // pointycastle reports a MAC mismatch as ArgumentError.
      throw const HiddenMessageDecryptionException(
          'ChaCha20-Poly1305 authentication failed '
          '(wrong passphrase or tampered data).');
    }
  }

  /// Raw RFC 8439 AEAD encryption: returns `ciphertext || tag`.
  static Uint8List seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List plaintext,
  }) =>
      _run(true, key, nonce, associatedData, plaintext);

  /// Raw RFC 8439 AEAD decryption of `ciphertext || tag`. Throws if the tag
  /// does not verify.
  static Uint8List open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List sealed,
  }) =>
      _run(false, key, nonce, associatedData, sealed);

  static Uint8List _run(
    bool forEncryption,
    Uint8List key,
    Uint8List nonce,
    Uint8List associatedData,
    Uint8List input,
  ) {
    final aead = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
      ..init(
        forEncryption,
        AEADParameters(KeyParameter(key), tagLength * 8, nonce, associatedData),
      );
    final out = Uint8List(aead.getOutputSize(input.length));
    var len = aead.processBytes(input, 0, input.length, out, 0);
    len += aead.doFinal(out, len);
    return Uint8List.sublistView(out, 0, len);
  }

  static void _checkPlatform() {
    if (!isSupported) {
      throw UnsupportedError(
        'ChaCha20-Poly1305 is not available on the web: pointycastle\'s '
        'Poly1305 needs 64-bit integers. Use AesSivCipher instead.',
      );
    }
  }

  Uint8List _key(String encryptionPassphrase, Uint8List associatedData) =>
      PassphraseKdf.derive(
        encryptionPassphrase: encryptionPassphrase,
        associatedData: associatedData,
        length: 32,
        iterations: iterations,
      );
}
