import 'error_correction_level.dart';
import 'version.dart';

/// The stream of encoded data codewords (payload + terminator + padding).
class DataCodewords {
  DataCodewords({
    required List<int> bytes,
    required this.version,
    required this.level,
  }) : bytes = List<int>.unmodifiable(bytes);

  /// The data codewords bytes.
  final List<int> bytes;

  /// The QR Version for this codeword sequence.
  final QrVersion version;

  /// The chosen Error Correction Level.
  final ErrorCorrectionLevel level;

  int get length => bytes.length;
  int operator [](int index) => bytes[index];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DataCodewords ||
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
      'DataCodewords(v${version.number}-${level.label}, count=${bytes.length})';
}
