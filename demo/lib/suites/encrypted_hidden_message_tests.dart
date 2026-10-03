import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// CLI test suite for the encrypted hidden-message channel.
class EncryptedHiddenMessageTests {
  EncryptedHiddenMessageTests._();

  static const _public = 'https://example.com/public-info';
  static const _positionKey = 'suite-position-key';
  static const _passphrase = 'suite-passphrase';

  static int runAll() {
    TerminalUtils.printSection(
        'Suite 4: Encrypted Hidden Message Channel (AES-SIV, ChaCha20-Poly1305)');
    var failures = 0;
    for (final cipher in <HiddenMessageCipher>[
      const AesSivCipher(),
      if (ChaCha20Poly1305Cipher.isSupported) ChaCha20Poly1305Cipher(),
    ]) {
      failures += _check('${cipher.name}: Unicode roundtrip', () {
        const hidden = 'Ünïcödé 🔑 مرحبا 你好';
        final enc = _encode(hidden, cipher);
        final dec = _decode(enc.matrix);
        return dec.hiddenText == hidden &&
                dec.public.text == _public &&
                dec.schemeId == cipher.schemeId
            ? 'v${enc.version.number}-${enc.level.label}'
            : null;
      });
      failures += _expectThrow<HiddenMessageDecryptionException>(
          '${cipher.name}: wrong passphrase throws', () {
        _decode(_encode('secret', cipher).matrix, passphrase: 'wrong');
      });
      failures += _expectThrow<HiddenMessageCryptoException>(
          '${cipher.name}: wrong position key throws', () {
        _decode(_encode('secret', cipher).matrix, positionKey: 'wrong');
      });
      failures += _check('${cipher.name}: capacity accounts for overhead', () {
        final cap = TwoLevelQr.hiddenMessageCapacity(
            version: 10, level: ErrorCorrectionLevel.high, cipher: cipher);
        final plainCap = TwoLevelQr.hiddenMessageCapacity(
            version: 10, level: ErrorCorrectionLevel.high);
        _encode('a' * cap, cipher, explicitVersion: 10);
        try {
          _encode('a' * (cap + 1), cipher, explicitVersion: 10);
          return null;
        } on ArgumentError {
          return cap == plainCap - 1 - cipher.overhead
              ? 'max $cap bytes at v10-H'
              : null;
        }
      });
    }
    failures += _expectThrow<HiddenMessageCryptoException>(
        'Plaintext QR rejected by encrypted decoder', () {
      final plain = TwoLevelQr.encodeWithHiddenMessage(
          publicText: _public, hiddenText: 'SECRET', key: _positionKey);
      _decode(plain.matrix);
    });
    failures += _expectThrow<ArgumentError>(
        'Equal position key and passphrase rejected', () {
      TwoLevelQr.encodeWithEncryptedHiddenMessage(
          publicText: _public,
          hiddenText: 'x',
          positionKey: 'same',
          encryptionPassphrase: 'same');
    });
    return failures;
  }

  static EncodeResult _encode(String hidden, HiddenMessageCipher cipher,
          {int? explicitVersion}) =>
      TwoLevelQr.encodeWithEncryptedHiddenMessage(
        publicText: _public,
        hiddenText: hidden,
        positionKey: _positionKey,
        encryptionPassphrase: _passphrase,
        cipher: cipher,
        explicitVersion: explicitVersion,
      );

  static EncryptedHiddenDecodeResult _decode(QrMatrix m,
          {String positionKey = _positionKey,
          String passphrase = _passphrase}) =>
      TwoLevelQr.decodeWithEncryptedHiddenMessage(m,
          positionKey: positionKey, encryptionPassphrase: passphrase);

  /// Runs [body]; a non-null return value means pass (used as detail text).
  static int _check(String name, String? Function() body) {
    try {
      final extra = body();
      TerminalUtils.printTestResult(name, extra != null, extra: extra);
      return extra != null ? 0 : 1;
    } catch (e) {
      TerminalUtils.printTestResult(name, false, extra: e.toString());
      return 1;
    }
  }

  static int _expectThrow<T>(String name, void Function() body) {
    try {
      body();
      TerminalUtils.printTestResult(name, false, extra: 'no exception');
      return 1;
    } catch (e) {
      final pass = e is T;
      TerminalUtils.printTestResult(name, pass,
          extra: pass ? '${e.runtimeType}' : 'wrong exception: $e');
      return pass ? 0 : 1;
    }
  }
}
