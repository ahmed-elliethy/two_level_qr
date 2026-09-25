import '../data/qr_tables.dart';
import 'error_correction_level.dart';

/// A QR symbol version (1..40) plus the capacity arithmetic that depends on
/// it. First-class checkpoint used by every stage of the pipeline.
class QrVersion {
  const QrVersion(this.number) : assert(number >= 1 && number <= 40, 'Version must be in 1..40');

  /// Version number, 1-based (1..40).
  final int number;

  /// Symbol side length in modules: 21 + 4*(v-1) = 17 + 4*v.
  int get size => 17 + 4 * number;

  /// Total codewords (data + ECC) available in this version.
  int get totalCodewords => QrTables.totalCodewords[number - 1];

  /// Alignment-pattern center coordinates for this version (ISO Table E.1).
  List<int> get alignmentCenters => QrTables.alignmentCenters[number - 1];

  /// Number of remainder bits (0..7) to append to the bitstream.
  int get remainderBits => QrTables.remainderBits[number - 1];

  /// Look up or find the minimum version required to hold [requiredDataBytes] for [level].
  static QrVersion findMinimumVersion({
    required int requiredDataBytes,
    required ErrorCorrectionLevel level,
    int minVersion = 1,
    int maxVersion = 40,
  }) {
    for (var v = minVersion; v <= maxVersion; v++) {
      if (dataCodewordsCapacity(v, level) >= requiredDataBytes) {
        return QrVersion(v);
      }
    }
    throw ArgumentError(
      'Data length ($requiredDataBytes bytes) exceeds max capacity for level ${level.label} at version $maxVersion',
    );
  }

  @override
  String toString() => 'QrVersion($number)';

  @override
  bool operator ==(Object other) => other is QrVersion && other.number == number;

  @override
  int get hashCode => number.hashCode;
}

/// Number of error-correction codewords per block for (version, level).
int ecCodewordsPerBlock(int versionNumber, ErrorCorrectionLevel level) {
  return QrTables.ecCharacteristics[versionNumber - 1][level.ordinal][0];
}

/// Block structure: `[shortBlockCount, shortDataPerBlock, longBlockCount, longDataPerBlock]`
/// per (version, level).
List<int> blockStructure(int versionNumber, ErrorCorrectionLevel level) {
  final entry = QrTables.ecCharacteristics[versionNumber - 1][level.ordinal];
  final count1 = entry[1];
  final data1 = entry[2];
  final count2 = entry[3];
  final data2 = entry[4];
  return [count1, data1, count2, data2];
}

/// Total DATA codewords for (version, level).
int dataCodewordsCapacity(int versionNumber, ErrorCorrectionLevel level) {
  final entry = QrTables.ecCharacteristics[versionNumber - 1][level.ordinal];
  final count1 = entry[1];
  final data1 = entry[2];
  final count2 = entry[3];
  final data2 = entry[4];
  return count1 * data1 + count2 * data2;
}
