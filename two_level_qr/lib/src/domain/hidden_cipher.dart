import 'dart:typed_data';

/// Contract for a cipher that protects the hidden message of an encrypted
/// two-level QR code.
///
/// Implement this class to plug in your own encryption scheme. The encoder
/// writes [schemeId] into the hidden channel as a one-byte header, so the
/// receiver can tell which cipher produced the payload. When decoding, the
/// cipher is looked up by that byte among the ciphers passed to
/// `TwoLevelQr.decodeWithEncryptedHiddenMessage`.
///
/// Scheme ID ranges:
/// * `0x01`–`0x7F`: reserved for the built-in ciphers of this package.
/// * `0x80`–`0xFE`: available for custom ciphers.
/// * `0x00` and `0xFF`: invalid.
///
/// Implementations must be authenticated: [decrypt] has to detect a wrong
/// passphrase, a modified ciphertext, or modified [associatedData] and throw
/// [HiddenMessageDecryptionException] instead of returning bytes.
abstract class HiddenMessageCipher {
  const HiddenMessageCipher();

  /// First scheme ID available to custom ciphers.
  static const int customSchemeIdMin = 0x80;

  /// Last scheme ID available to custom ciphers.
  static const int customSchemeIdMax = 0xFE;

  /// One-byte identifier written in the hidden-channel header.
  int get schemeId;

  /// Human-readable name, e.g. `'AES-SIV-CMAC-512'`.
  String get name;

  /// Number of bytes [encrypt] adds to the plaintext (nonce, tag, ...).
  ///
  /// Used for capacity calculations: it must equal
  /// `encrypt(...).length - plaintext.length` for every input.
  int get overhead;

  /// Encrypts [plaintext] with a key derived from [encryptionPassphrase],
  /// authenticating [associatedData] as well.
  Uint8List encrypt({
    required String encryptionPassphrase,
    required Uint8List plaintext,
    required Uint8List associatedData,
  });

  /// Decrypts [ciphertext] produced by [encrypt].
  ///
  /// Must throw [HiddenMessageDecryptionException] on any authentication or
  /// format failure. It must never return unauthenticated bytes.
  Uint8List decrypt({
    required String encryptionPassphrase,
    required Uint8List ciphertext,
    required Uint8List associatedData,
  });
}

/// Base class of every error raised while decoding an encrypted hidden
/// message. Catch this to handle all failure modes at once.
///
/// When one of these is thrown, no hidden text is returned: the encrypted
/// decoder never falls back to interpreting the channel as plaintext.
abstract class HiddenMessageCryptoException implements Exception {
  const HiddenMessageCryptoException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The hidden channel does not contain a well-formed encrypted envelope, for
/// example because the length prefix is out of range. A wrong position key or
/// ratio usually ends here.
class HiddenMessageFormatException extends HiddenMessageCryptoException {
  const HiddenMessageFormatException(super.message);
}

/// The envelope names a scheme ID that is invalid or that none of the
/// supplied ciphers handles.
class UnsupportedHiddenCipherException extends HiddenMessageCryptoException {
  UnsupportedHiddenCipherException(this.schemeId)
      : super('No cipher registered for scheme ID '
            '0x${schemeId.toRadixString(16).padLeft(2, '0')}.');

  final int schemeId;
}

/// Authentication failed: wrong encryption passphrase, wrong position key,
/// tampered payload, or a payload moved onto a different public text.
class HiddenMessageDecryptionException extends HiddenMessageCryptoException {
  const HiddenMessageDecryptionException(super.message);
}
