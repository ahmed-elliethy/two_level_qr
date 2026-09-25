import 'version.dart';

/// Decoded and validated Version Information for symbols of version 7 and larger (ISO/IEC 18004 §8.10).
class VersionInfo {
  const VersionInfo({
    required this.version,
    required this.bits18,
  });

  /// The QR Version (7..40).
  final QrVersion version;

  /// The 18-bit sequence (6 data bits + 12 BCH error correction bits).
  final int bits18;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VersionInfo &&
          other.version == version &&
          other.bits18 == bits18;

  @override
  int get hashCode => Object.hash(version, bits18);

  @override
  String toString() =>
      'VersionInfo(v=${version.number}, bits18=0x${bits18.toRadixString(16).padLeft(5, '0')})';
}
