// Runnable tour of the two_level_qr API: `dart run example/main.dart`.
import 'package:two_level_qr/two_level_qr.dart';

void main() {
  // ---------------------------------------------------------------------------
  // 1. A normal QR code.
  // ---------------------------------------------------------------------------
  final qr = TwoLevelQr.encode('https://example.com');
  print('1) Plain QR: ${qr.version} -> "${TwoLevelQr.decode(qr.matrix).text}"');
  printMatrix(qr.matrix);

  // ---------------------------------------------------------------------------
  // 2. A hidden message in the Reed-Solomon error channel (plaintext mode).
  //
  // `key` only chooses WHERE the hidden bytes go. The bytes themselves are not
  // encrypted: anyone who error-corrects the code can see them, scrambled.
  // ---------------------------------------------------------------------------
  final plain = TwoLevelQr.encodeWithHiddenMessage(
    publicText: 'https://example.com',
    hiddenText: 'not really secret',
    key: 'position-key',
  );
  final plainDec =
      TwoLevelQr.decodeWithHiddenMessage(plain.matrix, key: 'position-key');
  print('\n2) Plaintext hidden message: "${plainDec.hiddenText}" '
      '(public: "${plainDec.public.text}")');

  // ---------------------------------------------------------------------------
  // 3. An encrypted hidden message.
  //
  // positionKey          -> where the hidden bytes go
  // encryptionPassphrase -> what they say (authenticated encryption)
  // The cipher's scheme ID is stored in the QR, so the receiver knows which
  // cipher to use. AES-SIV is the default and works on every platform.
  // ---------------------------------------------------------------------------
  const positionKey = 'position-key';
  const passphrase = 'correct horse battery staple';

  final capacity = TwoLevelQr.hiddenMessageCapacity(
    version: 10,
    level: ErrorCorrectionLevel.high,
    cipher: const AesSivCipher(),
  );
  print(
      '\n3) Encrypted capacity of a v10-H code with AES-SIV: $capacity bytes');

  final secret = TwoLevelQr.encodeWithEncryptedHiddenMessage(
    publicText: 'https://example.com',
    hiddenText: 'Meet at 9pm 🔑',
    positionKey: positionKey,
    encryptionPassphrase: passphrase,
  );
  final secretDec = TwoLevelQr.decodeWithEncryptedHiddenMessage(
    secret.matrix,
    positionKey: positionKey,
    encryptionPassphrase: passphrase,
  );
  print('   ${secretDec.cipherName} in ${secret.version}: '
      '"${secretDec.hiddenText}"');
  printMatrix(secret.matrix);

  // A wrong passphrase never yields text; it throws.
  try {
    TwoLevelQr.decodeWithEncryptedHiddenMessage(
      secret.matrix,
      positionKey: positionKey,
      encryptionPassphrase: 'wrong passphrase',
    );
  } on HiddenMessageCryptoException catch (e) {
    print('   Wrong passphrase -> $e');
  }

  // ChaCha20-Poly1305 is also built in (native platforms only).
  if (ChaCha20Poly1305Cipher.isSupported) {
    final chacha = TwoLevelQr.encodeWithEncryptedHiddenMessage(
      publicText: 'https://example.com',
      hiddenText: 'Same secret, other cipher',
      positionKey: positionKey,
      encryptionPassphrase: passphrase,
      cipher: ChaCha20Poly1305Cipher(),
    );
    final chachaDec = TwoLevelQr.decodeWithEncryptedHiddenMessage(
      chacha.matrix,
      positionKey: positionKey,
      encryptionPassphrase: passphrase,
    );
    print('   ${chachaDec.cipherName} in ${chacha.version}: '
        '"${chachaDec.hiddenText}"');
  }
}

/// Prints [matrix] using two characters per module, with a quiet zone.
void printMatrix(QrMatrix matrix) {
  final quiet = '  ' * (matrix.size + 4);
  print(quiet);
  for (var y = 0; y < matrix.size; y++) {
    final row = StringBuffer('    ');
    for (var x = 0; x < matrix.size; x++) {
      row.write(matrix.isDark(x, y) ? '██' : '  ');
    }
    print('$row    ');
  }
  print(quiet);
}
