# Change Log
All notable changes to this project will be documented in this file.
 
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).
 
# [0.1.0] - 2026-09-25

Initial release

# [0.1.1] - 2026-09-25

Adding files required for publishing to pub.dev

# [0.2.0] - 2026-10-01

### Added
- Encrypted hidden messages: `TwoLevelQr.encodeWithEncryptedHiddenMessage` and
  `TwoLevelQr.decodeWithEncryptedHiddenMessage`, with separate `positionKey`
  and `encryptionPassphrase`. Decoding never falls back to plaintext; failures
  throw `HiddenMessageCryptoException` subclasses.
- Pluggable `HiddenMessageCipher` contract. A one-byte scheme ID in the hidden
  channel tells the receiver which cipher was used.
- Built-in ciphers: `AesSivCipher` (AES-SIV-CMAC-512, default, all platforms)
  and `ChaCha20Poly1305Cipher` (native platforms), using pointycastle.
- `PassphraseKdf` (PBKDF2-HMAC-SHA256) with a configurable iteration count
  (default 1000; `kdfIterations` on the facade, `iterations` on the ciphers).
- `TwoLevelQr.hiddenMessageCapacity` for plaintext and encrypted modes.
- `EncodeHiddenQr.executeWithPayload`, `DecodeHiddenQr.extractChannel`,
  `EncodeResult.hiddenCipherSchemeId`, and
  `HiddenMessageCapacityException.overheadBytes`.
- `example/main.dart`.
- Test vectors: RFC 5297, Wycheproof AES-SIV-CMAC, RFC 8439, RFC 7914.

### Fixed
- The package now compiles for the web. The keyed position scheduler emulates
  its 64-bit arithmetic, so schedules are bit-identical on every platform and
  codes created with 0.1.x still decode.
- Automatic version bumping only retries on capacity overflow instead of on
  any `ArgumentError`.

### Changed
- Minimum Dart SDK is now 3.2.0 (required by pointycastle 4).
- Plaintext hidden-message output is unchanged byte for byte (covered by a
  golden test).
