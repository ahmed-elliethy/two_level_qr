@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('example/main.dart runs and shows every section', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'example/main.dart'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final out = result.stdout as String;
    expect(out, contains('1) Plain QR'));
    expect(out, contains('"not really secret"'));
    expect(out, contains('AES-SIV-CMAC-512'));
    expect(out, contains('"Meet at 9pm 🔑"'));
    expect(out, contains('HiddenMessageDecryptionException'));
    expect(out, contains('ChaCha20-Poly1305'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
