import 'dart:io';
import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// Demonstrates why the hidden channel needs encryption, then encodes and
/// decodes an encrypted two-level QR code.
class EncryptedHiddenMessageDemo {
  EncryptedHiddenMessageDemo._();

  static void runDemo({
    String publicText = 'https://example.com/public-info',
    String hiddenText = 'SECRET_KEY_12345',
    String positionKey = 'demo-position-key',
    String encryptionPassphrase = 'demo-encryption-passphrase',
    String cipherName = 'aes-siv',
    double ratio = 0.8,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
  }) {
    TerminalUtils.printHeader(
      'Encrypted Two-Level QR Hidden Message Demo',
      subtitle: 'Position key = where, passphrase = what',
    );

    final cipher = parseCipher(cipherName);

    // 1. The problem: plaintext error values are visible without the key.
    stdout.writeln(TerminalUtils.info(
        '\n[1] Plaintext mode: what an attacker WITHOUT the key sees...'));
    final plain = TwoLevelQr.encodeWithHiddenMessage(
      publicText: publicText,
      hiddenText: hiddenText,
      key: positionKey,
      ratio: ratio,
      level: level,
    );
    TerminalUtils.printSection('Attacker View (plaintext mode)');
    _printAttackerView(plain.matrix);
    stdout.writeln(TerminalUtils.warning(
        '  The secret\'s bytes appear as error values, only shuffled.'));

    // 2. Encrypted encode.
    stdout.writeln(TerminalUtils.info(
        '\n[2] Encoding with ${cipher.name}...'));
    final stopwatch = Stopwatch()..start();
    late final EncodeResult enc;
    try {
      enc = TwoLevelQr.encodeWithEncryptedHiddenMessage(
        publicText: publicText,
        hiddenText: hiddenText,
        positionKey: positionKey,
        encryptionPassphrase: encryptionPassphrase,
        cipher: cipher,
        ratio: ratio,
        level: level,
      );
    } on HiddenMessageCapacityException catch (e) {
      TerminalUtils.printSection('Capacity Error');
      stdout.writeln(TerminalUtils.error('  $e'));
      return;
    } on ArgumentError catch (e) {
      TerminalUtils.printSection('Argument Error');
      stdout.writeln(TerminalUtils.error('  ${e.message}'));
      return;
    }
    stopwatch.stop();

    final overhead = 3 + cipher.overhead;
    TerminalUtils.printMetric('Public Message', '"$publicText"');
    TerminalUtils.printMetric('Hidden Message', '"$hiddenText"');
    TerminalUtils.printMetric('Cipher',
        '${cipher.name} (scheme 0x${cipher.schemeId.toRadixString(16).padLeft(2, '0')})');
    TerminalUtils.printMetric('Symbol Version',
        'v${enc.version.number} (${enc.matrix.size}x${enc.matrix.size}) '
        'vs v${plain.version.number} in plaintext mode');
    TerminalUtils.printMetric('Channel Bytes',
        '${enc.hiddenBytes!.length} = ${enc.hiddenBytes!.length - overhead} '
        'message + $overhead framing/overhead');
    TerminalUtils.printMetric(
        'Capacity at v${enc.version.number}',
        TwoLevelQr.hiddenMessageCapacity(
            version: enc.version.number,
            level: level,
            ratio: ratio,
            cipher: cipher),
        unit: 'message bytes');
    TerminalUtils.printMetric(
        'Encode Time', '${stopwatch.elapsedMilliseconds} ms');

    stdout.writeln(TerminalUtils.muted('\n--- Encrypted Two-Level QR Matrix ---'));
    TerminalUtils.printQrMatrix(enc.matrix);

    TerminalUtils.printSection('Attacker View (encrypted mode)');
    _printAttackerView(enc.matrix);

    // 3. Correct decode.
    stdout.writeln(TerminalUtils.info('\n[3] Decoding with the correct secrets...'));
    final dec = TwoLevelQr.decodeWithEncryptedHiddenMessage(
      enc.matrix,
      positionKey: positionKey,
      encryptionPassphrase: encryptionPassphrase,
      ratio: ratio,
    );
    TerminalUtils.printMetric(
        'Recovered Public', TerminalUtils.success('"${dec.public.text}"'));
    TerminalUtils.printMetric(
        'Recovered Hidden', TerminalUtils.success('"${dec.hiddenText}"'));
    TerminalUtils.printMetric('Detected Cipher', dec.cipherName);

    // 4. Wrong secrets: exceptions, never plaintext.
    stdout.writeln(TerminalUtils.warning('\n[4] Decoding with WRONG secrets...'));
    _tryWrong('Wrong passphrase', () {
      TwoLevelQr.decodeWithEncryptedHiddenMessage(enc.matrix,
          positionKey: positionKey,
          encryptionPassphrase: '$encryptionPassphrase-wrong',
          ratio: ratio);
    });
    _tryWrong('Wrong position key', () {
      TwoLevelQr.decodeWithEncryptedHiddenMessage(enc.matrix,
          positionKey: '$positionKey-wrong',
          encryptionPassphrase: encryptionPassphrase,
          ratio: ratio);
    });
    stdout.writeln(TerminalUtils.success(
        '\n✓ Failures raise exceptions; no plaintext fallback.\n'));
  }

  /// Maps a CLI cipher name to a built-in cipher.
  static HiddenMessageCipher parseCipher(String name) {
    switch (name.toLowerCase()) {
      case 'chacha20':
      case 'chacha20-poly1305':
        return ChaCha20Poly1305Cipher();
      case 'aes-siv':
      default:
        return const AesSivCipher();
    }
  }

  static void _tryWrong(String label, void Function() decode) {
    try {
      decode();
      TerminalUtils.printMetric(label, TerminalUtils.error('UNEXPECTED SUCCESS'));
    } on HiddenMessageCryptoException catch (e) {
      TerminalUtils.printMetric(
          label, TerminalUtils.success('${e.runtimeType}'));
    }
  }

  /// Shows the nonzero `raw ^ corrected` bytes of each block, which anyone
  /// can compute after standard Reed-Solomon correction.
  static void _printAttackerView(QrMatrix matrix) {
    final pub = TwoLevelQr.decode(matrix);
    final raw = const BlockInterleaver().deinterleave(
        rawCodewords: pub.rawCodewords, version: pub.version, level: pub.level);
    final cor = pub.correctedCodewords.blocks;
    for (var b = 0; b < raw.length; b++) {
      final shown = StringBuffer();
      for (var i = 0; i < cor[b].dataCodewords.length; i++) {
        final e = raw[b].dataCodewords[i] ^ cor[b].dataCodewords[i];
        if (e == 0) continue;
        shown.write(e >= 0x20 && e < 0x7F
            ? String.fromCharCode(e)
            : TerminalUtils.muted('·'));
      }
      if (shown.isNotEmpty) {
        TerminalUtils.printMetric('Block $b errors', shown.toString());
      }
    }
  }
}
