import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Derives cipher keys from an encryption passphrase with
/// PBKDF2-HMAC-SHA256 (RFC 8018).
///
/// The salt is `SHA-256("two_level_qr/kdf/v1" || associatedData)[0..16]`.
/// The associated data already contains the scheme ID and the public text, so
/// every QR code gets its own salt without spending hidden-channel capacity.
class PassphraseKdf {
  PassphraseKdf._();

  /// Default PBKDF2 iteration count.
  ///
  /// Deliberately low (proof-of-concept value) so encoding and decoding stay
  /// fast on every platform, including the web. For production, raise it via
  /// the cipher's `iterations` (or the facade's `kdfIterations`); OWASP
  /// recommends 600,000 for PBKDF2-HMAC-SHA256. Measured cost in this pure
  /// Dart implementation: ~0.7 s per 100k iterations on the VM and ~2.6 s
  /// on the web. Encoder and decoder must use the same value.
  static const int defaultIterations = 1000;

  static final Uint8List _saltDomain =
      Uint8List.fromList(utf8.encode('two_level_qr/kdf/v1'));

  /// Derives a key of [length] bytes from [encryptionPassphrase].
  static Uint8List derive({
    required String encryptionPassphrase,
    required Uint8List associatedData,
    required int length,
    int iterations = defaultIterations,
  }) {
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'must be >= 1');
    }
    final digest = SHA256Digest()
      ..update(_saltDomain, 0, _saltDomain.length)
      ..update(associatedData, 0, associatedData.length);
    final hash = Uint8List(digest.digestSize);
    digest.doFinal(hash, 0);
    final salt = Uint8List.sublistView(hash, 0, 16);

    return pbkdf2HmacSha256(
      password: Uint8List.fromList(utf8.encode(encryptionPassphrase)),
      salt: salt,
      iterations: iterations,
      length: length,
    );
  }

  /// Raw PBKDF2-HMAC-SHA256.
  static Uint8List pbkdf2HmacSha256({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int length,
  }) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, length));
    return kdf.process(password);
  }
}
