import 'dart:convert';
import 'dart:typed_data';

import '../data/ciphers/aes_siv.dart';
import '../domain/error_correction_level.dart';
import '../domain/hidden_cipher.dart';
import '../domain/hidden_message.dart';
import '../domain/mask_pattern.dart';
import '../encode_result.dart';
import 'encode_hidden_qr.dart';
import 'hidden_envelope.dart';

/// Use case that encrypts a hidden message with a [HiddenMessageCipher] and
/// embeds it in the Reed-Solomon error channel of a QR code.
///
/// Hidden-channel layout: `[len_hi][len_lo] || schemeId || cipherOutput`.
/// Every byte, including the framing and the cipher overhead, is placed at
/// [positionKey]-derived positions and counts against the per-block budget
/// set by `ratio`.
class EncodeEncryptedHiddenQr {
  EncodeEncryptedHiddenQr({EncodeHiddenQr? encodeHiddenQr})
      : _encodeHiddenQr = encodeHiddenQr ?? EncodeHiddenQr();

  final EncodeHiddenQr _encodeHiddenQr;

  /// Encodes [publicText] normally and hides [hiddenText], encrypted with
  /// [cipher] (default [AesSivCipher]) under [encryptionPassphrase].
  ///
  /// [positionKey] selects where the errors go; [encryptionPassphrase]
  /// protects what they contain. They must differ.
  ///
  /// Version selection matches [EncodeHiddenQr.execute], with the cipher
  /// overhead included in the size: with [explicitVersion] a message that
  /// does not fit throws [ArgumentError]; otherwise the version is increased
  /// up to 40 and [HiddenMessageCapacityException] is thrown if none fits.
  EncodeResult execute({
    required String publicText,
    required String hiddenText,
    required String positionKey,
    required String encryptionPassphrase,
    HiddenMessageCipher cipher = const AesSivCipher(),
    double ratio = 0.8,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
    int? explicitVersion,
    MaskPattern? explicitMask,
  }) {
    _validateRatio(ratio);
    if (encryptionPassphrase.isEmpty) {
      throw ArgumentError.value(
          encryptionPassphrase, 'encryptionPassphrase', 'must not be empty');
    }
    if (positionKey == encryptionPassphrase) {
      throw ArgumentError(
        'positionKey and encryptionPassphrase must be different secrets.',
      );
    }
    HiddenEnvelope.validateCipher(cipher);

    // Encrypt once: the associated data does not depend on the QR version,
    // and a single encryption means a single nonce for nonce-based ciphers.
    final plaintext = Uint8List.fromList(utf8.encode(hiddenText));
    final ciphertext = cipher.encrypt(
      encryptionPassphrase: encryptionPassphrase,
      plaintext: plaintext,
      associatedData:
          HiddenEnvelope.associatedData(cipher.schemeId, publicText),
    );
    if (ciphertext.length != plaintext.length + cipher.overhead) {
      throw StateError(
        '${cipher.name} produced ${ciphertext.length} bytes for a '
        '${plaintext.length}-byte message, but declares an overhead of '
        '${cipher.overhead}.',
      );
    }

    return _encodeHiddenQr.executeWithPayload(
      publicText: publicText,
      hiddenText: hiddenText,
      payload: [cipher.schemeId, ...ciphertext],
      options: HiddenEncodeOptions(key: positionKey, ratio: ratio),
      level: level,
      explicitVersion: explicitVersion,
      explicitMask: explicitMask,
      userPayloadBytes: plaintext.length,
      overheadBytes: 1 + cipher.overhead,
      hiddenCipherSchemeId: cipher.schemeId,
    );
  }
}

void _validateRatio(double ratio) {
  if (!(ratio > 0.0 && ratio <= 1.0)) {
    throw ArgumentError.value(ratio, 'ratio', 'must be in (0.0, 1.0]');
  }
}
