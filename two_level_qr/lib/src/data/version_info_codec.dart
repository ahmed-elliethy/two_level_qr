import '../domain/ports.dart';
import '../domain/version.dart';
import '../domain/version_info.dart';
import 'bch.dart';

/// Codec for encoding and decoding 18-bit Version Information (for versions 7..40).
class VersionInfoCodec implements VersionInfoCodecPort {
  const VersionInfoCodec();

  @override
  VersionInfo encode(QrVersion version) {
    if (version.number < 7) {
      throw ArgumentError.value(
        version.number,
        'version',
        'Version information is only present on QR Code versions 7..40',
      );
    }
    final bits18 = BchCodec.encodeVersion(version.number);
    return VersionInfo(
      version: version,
      bits18: bits18,
    );
  }

  @override
  VersionInfo decode(int versionBits) {
    final v = BchCodec.decodeVersion(versionBits);
    if (v == null) {
      throw FormatException(
        'Invalid or uncorrectable version information bits: 0x${versionBits.toRadixString(16)}',
      );
    }
    return VersionInfo(
      version: QrVersion(v),
      bits18: versionBits,
    );
  }
}
