import 'dart:convert';

import '../domain/hidden_cipher.dart';
import '../domain/hidden_message.dart';
import '../domain/qr_matrix.dart';
import 'decode_hidden_qr.dart';
import 'hidden_envelope.dart';

/// Use case that extracts and decrypts the hidden message of an encrypted
/// two-level QR code.
///
/// The scheme byte in the hidden channel selects the cipher. Every failure
/// throws a [HiddenMessageCryptoException]; this use case never falls back to
/// reading the channel as plaintext.
class DecodeEncryptedHiddenQr {
  DecodeEncryptedHiddenQr({DecodeHiddenQr? decodeHiddenQr})
      : _decodeHiddenQr = decodeHiddenQr ?? DecodeHiddenQr();

  final DecodeHiddenQr _decodeHiddenQr;

  /// Decodes [matrix] and decrypts its hidden message.
  ///
  /// [positionKey], [encryptionPassphrase] and [ratio] must match the values
  /// used when encoding. [ciphers] lists the schemes this receiver accepts;
  /// it defaults to the built-in AES-SIV and ChaCha20-Poly1305 ciphers with
  /// their default PBKDF2 iteration counts.
  ///
  /// Throws:
  /// * [HiddenMessageFormatException] if the channel has no valid envelope
  ///   (typical for a wrong position key or ratio, or a plaintext QR).
  /// * [UnsupportedHiddenCipherException] if no cipher matches the scheme ID.
  /// * [HiddenMessageDecryptionException] if authentication fails.
  EncryptedHiddenDecodeResult execute(
    QrMatrix matrix, {
    required String positionKey,
    required String encryptionPassphrase,
    double ratio = 0.8,
    List<HiddenMessageCipher>? ciphers,
  }) {
    if (!(ratio > 0.0 && ratio <= 1.0)) {
      throw ArgumentError.value(ratio, 'ratio', 'must be in (0.0, 1.0]');
    }
    if (encryptionPassphrase.isEmpty) {
      throw ArgumentError.value(
          encryptionPassphrase, 'encryptionPassphrase', 'must not be empty');
    }
    final registry =
        HiddenEnvelope.registry(ciphers ?? HiddenEnvelope.defaultCiphers());

    final (public, channel) = _decodeHiddenQr.extractChannel(
      matrix,
      key: positionKey,
      ratio: ratio,
    );

    // 1-2. Strictly parse the envelope and select the cipher.
    final (cipher, ciphertext) = HiddenEnvelope.parse(channel, registry);
    final schemeId = cipher.schemeId;

    // 3. Authenticate and decrypt. No plaintext fallback.
    final plaintext = cipher.decrypt(
      encryptionPassphrase: encryptionPassphrase,
      ciphertext: ciphertext,
      associatedData: HiddenEnvelope.associatedData(schemeId, public.text),
    );
    final String hiddenText;
    try {
      hiddenText = utf8.decode(plaintext);
    } on FormatException {
      throw const HiddenMessageFormatException(
          'Decrypted hidden message is not valid UTF-8.');
    }

    return EncryptedHiddenDecodeResult(
      public: public,
      schemeId: schemeId,
      cipherName: cipher.name,
      hiddenBytes: plaintext,
      hiddenText: hiddenText,
    );
  }
}
