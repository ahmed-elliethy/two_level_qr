import 'error_correction_level.dart';
import 'version.dart';

/// Raw codewords extracted directly from a scanned matrix (after unmasking),
/// which may contain noise or bit errors.
class RawCodewords {
  RawCodewords({
    required List<int> bytes,
    required this.version,
    required this.level,
  }) : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;
  final QrVersion version;
  final ErrorCorrectionLevel level;

  int get length => bytes.length;
  int operator [](int index) => bytes[index];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RawCodewords ||
        other.version != version ||
        other.level != level ||
        other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(version, level, Object.hashAll(bytes));

  @override
  String toString() =>
      'RawCodewords(v${version.number}-${level.label}, count=${bytes.length})';
}
