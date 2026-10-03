import 'dart:convert';
import 'dart:typed_data';

import '../data/ciphers/aes_siv.dart';
import '../data/ciphers/chacha20_poly1305_cipher.dart';
import '../data/ciphers/passphrase_kdf.dart';
import '../data/keyed_error_scheduler.dart';
import '../domain/error_correction_level.dart';
import '../domain/hidden_cipher.dart';
import '../domain/rs_block.dart';
import '../domain/version.dart';

/// Shared rules for the encrypted hidden-channel envelope:
/// `[len_hi][len_lo] || schemeId || cipherOutput`.
class HiddenEnvelope {
  HiddenEnvelope._();

  /// Length prefix (2) plus scheme byte (1).
  static const int framingBytes = 3;

  static final List<int> _adDomain = utf8.encode('two_level_qr/enc/v1');

  /// Associated data authenticated by the cipher:
  /// `utf8("two_level_qr/enc/v1") || schemeId || utf8(publicText)`.
  static Uint8List associatedData(int schemeId, String publicText) =>
      Uint8List.fromList([..._adDomain, schemeId, ...utf8.encode(publicText)]);

  /// True for the ciphers shipped with this package.
  static bool isBuiltIn(HiddenMessageCipher cipher) =>
      (cipher is AesSivCipher && cipher.schemeId == AesSivCipher.id) ||
      (cipher is ChaCha20Poly1305Cipher &&
          cipher.schemeId == ChaCha20Poly1305Cipher.id);

  /// Throws [ArgumentError] unless [cipher] is a built-in or uses a scheme ID
  /// in the custom range `0x80`–`0xFE`, and its overhead is non-negative.
  static void validateCipher(HiddenMessageCipher cipher) {
    if (cipher.overhead < 0) {
      throw ArgumentError.value(
          cipher.overhead, 'overhead', '${cipher.name}: must be >= 0');
    }
    if (isBuiltIn(cipher)) return;
    final id = cipher.schemeId;
    if (id < HiddenMessageCipher.customSchemeIdMin ||
        id > HiddenMessageCipher.customSchemeIdMax) {
      throw ArgumentError.value(
        id,
        'schemeId',
        '${cipher.name}: custom ciphers must use scheme IDs '
            '0x80-0xFE (0x01-0x7F are reserved for built-in ciphers)',
      );
    }
  }

  /// Validates [ciphers] and indexes them by scheme ID.
  static Map<int, HiddenMessageCipher> registry(
      List<HiddenMessageCipher> ciphers) {
    final byId = <int, HiddenMessageCipher>{};
    for (final c in ciphers) {
      validateCipher(c);
      if (byId.containsKey(c.schemeId)) {
        throw ArgumentError(
          'Duplicate cipher scheme ID 0x${c.schemeId.toRadixString(16)}: '
          '${byId[c.schemeId]!.name} and ${c.name}.',
        );
      }
      byId[c.schemeId] = c;
    }
    return byId;
  }

  /// Strictly parses the hidden [channel] bytes
  /// (`[len_hi][len_lo] || schemeId || cipherOutput || unused...`) and picks
  /// the cipher for its scheme ID from [registry].
  ///
  /// Throws [HiddenMessageFormatException] for a malformed length and
  /// [UnsupportedHiddenCipherException] for an unknown scheme ID.
  static (HiddenMessageCipher, Uint8List) parse(
    List<int> channel,
    Map<int, HiddenMessageCipher> registry,
  ) {
    if (channel.length < framingBytes) {
      throw HiddenMessageFormatException(
        'Hidden channel holds only ${channel.length} bytes; an encrypted '
        'envelope needs at least $framingBytes.',
      );
    }
    final length = (channel[0] << 8) | channel[1];
    if (length < 1) {
      throw const HiddenMessageFormatException(
          'Envelope length is 0; no scheme byte present.');
    }
    if (2 + length > channel.length) {
      throw HiddenMessageFormatException(
        'Envelope length $length exceeds the ${channel.length - 2} bytes '
        'available in the hidden channel.',
      );
    }
    final schemeId = channel[2];
    final cipher = registry[schemeId];
    if (cipher == null) {
      throw UnsupportedHiddenCipherException(schemeId);
    }
    final ciphertext = Uint8List.fromList(channel.sublist(3, 2 + length));
    if (ciphertext.length < cipher.overhead) {
      throw HiddenMessageFormatException(
        '${cipher.name} payload is ${ciphertext.length} bytes, shorter than '
        'its ${cipher.overhead}-byte overhead.',
      );
    }
    return (cipher, ciphertext);
  }

  /// Ciphers recognized by the decoder when none are specified, using
  /// [iterations] for their key derivation. ChaCha20-Poly1305 is left out on
  /// platforms that cannot run it (the web).
  static List<HiddenMessageCipher> defaultCiphers({
    int iterations = PassphraseKdf.defaultIterations,
  }) =>
      [
        AesSivCipher(iterations: iterations),
        if (ChaCha20Poly1305Cipher.isSupported)
          ChaCha20Poly1305Cipher(iterations: iterations),
      ];

  /// Number of hidden-channel bytes available at [version]/[level]/[ratio].
  static int channelCapacity({
    required int version,
    required ErrorCorrectionLevel level,
    required double ratio,
  }) {
    final s = blockStructure(version, level);
    final ec = ecCodewordsPerBlock(version, level);
    final blocks = [
      for (var b = 0; b < s[0] + s[2]; b++)
        RsBlock(
          blockIndex: b,
          dataCodewords: List<int>.filled(b < s[0] ? s[1] : s[3], 0),
          eccCodewords: List<int>.filled(ec, 0),
        ),
    ];
    return KeyedErrorScheduler(key: '', ratio: ratio)
        .computeCapacity(blocks)
        .totalBytes;
  }

  /// Largest hidden message, in UTF-8 bytes, that fits at
  /// [version]/[level]/[ratio]: plaintext mode when [cipher] is `null`,
  /// encrypted mode otherwise. Never negative.
  static int messageCapacity({
    required int version,
    required ErrorCorrectionLevel level,
    required double ratio,
    HiddenMessageCipher? cipher,
  }) {
    final overhead = cipher == null ? 2 : framingBytes + cipher.overhead;
    final free = channelCapacity(version: version, level: level, ratio: ratio) -
        overhead;
    return free < 0 ? 0 : free;
  }
}
