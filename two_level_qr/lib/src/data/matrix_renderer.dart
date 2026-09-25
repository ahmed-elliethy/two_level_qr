import '../domain/error_correction_level.dart';
import '../domain/final_codewords.dart';
import '../domain/format_info.dart';
import '../domain/ports.dart';
import '../domain/qr_matrix.dart';
import '../domain/raw_codewords.dart';
import '../domain/version.dart';
import '../domain/version_info.dart';
import 'format_info_codec.dart';
import 'version_info_codec.dart';

/// Renders QR function patterns, reserved areas, and data bit layouts into [QrMatrix].
class MatrixRenderer implements MatrixRendererPort {
  const MatrixRenderer({
    this.formatCodec = const FormatInfoCodec(),
    this.versionCodec = const VersionInfoCodec(),
  });

  final FormatInfoCodecPort formatCodec;
  final VersionInfoCodecPort versionCodec;

  @override
  ({QrMatrix matrix, ModuleRegistry registry}) createBaseMatrix(QrVersion version) {
    final size = version.size;
    final matrix = QrMatrix.allLight(size);
    final registry = ModuleRegistry(size);

    // 1. Finder patterns and separators (3 corners)
    _placeFinderAndSeparator(matrix, registry, 0, 0); // Top-Left
    _placeFinderAndSeparator(matrix, registry, size - 7, 0); // Top-Right
    _placeFinderAndSeparator(matrix, registry, 0, size - 7); // Bottom-Left

    // 2. Timing patterns (Row 6 and Column 6)
    for (var x = 8; x < size - 8; x++) {
      final isDark = (x % 2 == 0);
      matrix.setDark(x, 6, dark: isDark);
      registry.reserve(x, 6);
    }
    for (var y = 8; y < size - 8; y++) {
      final isDark = (y % 2 == 0);
      matrix.setDark(6, y, dark: isDark);
      registry.reserve(6, y);
    }

    // 3. Alignment patterns (versions >= 2)
    final centers = version.alignmentCenters;
    for (final cy in centers) {
      for (final cx in centers) {
        if (_overlapsFinder(cx, cy, size)) continue;
        _placeAlignmentPattern(matrix, registry, cx, cy);
      }
    }

    // 4. Dark module: always at (8, 4*version + 9) = (8, size - 8)
    matrix.setDark(8, size - 8, dark: true);
    registry.reserve(8, size - 8);

    // 5. Reserve format information areas
    _reserveFormatAreas(registry, size);

    // 6. Reserve version information areas (versions >= 7)
    if (version.number >= 7) {
      _reserveVersionAreas(registry, size);
    }

    return (matrix: matrix, registry: registry);
  }

  @override
  void placeData({
    required QrMatrix matrix,
    required ModuleRegistry registry,
    required FinalCodewords finalCodewords,
  }) {
    final size = matrix.size;
    final bits = finalCodewords.bitBuffer.bits;
    var bitIndex = 0;
    var upwards = true;

    for (var x = size - 1; x > 0; x -= 2) {
      // Column 6 is the vertical timing pattern — skip it
      if (x == 6) x--;

      final yStart = upwards ? size - 1 : 0;
      final yEnd = upwards ? -1 : size;
      final yStep = upwards ? -1 : 1;

      for (var y = yStart; y != yEnd; y += yStep) {
        for (var c = 0; c < 2; c++) {
          final px = x - c;
          if (!registry.isReserved(px, y)) {
            final isDark = (bitIndex < bits.length) ? (bits[bitIndex++] == 1) : false;
            matrix.setDark(px, y, dark: isDark);
          }
        }
      }
      upwards = !upwards;
    }
  }

  @override
  RawCodewords extractData({
    required QrMatrix matrix,
    required ModuleRegistry registry,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) {
    final size = matrix.size;
    final bits = <int>[];
    var upwards = true;

    for (var x = size - 1; x > 0; x -= 2) {
      if (x == 6) x--;

      final yStart = upwards ? size - 1 : 0;
      final yEnd = upwards ? -1 : size;
      final yStep = upwards ? -1 : 1;

      for (var y = yStart; y != yEnd; y += yStep) {
        for (var c = 0; c < 2; c++) {
          final px = x - c;
          if (!registry.isReserved(px, y)) {
            bits.add(matrix.isDark(px, y) ? 1 : 0);
          }
        }
      }
      upwards = !upwards;
    }

    // Convert bits to byte codewords
    final totalCodewordsCount = version.totalCodewords;
    final bytes = List<int>.filled(totalCodewordsCount, 0);
    for (var i = 0; i < totalCodewordsCount; i++) {
      var val = 0;
      for (var b = 0; b < 8; b++) {
        final bitIdx = i * 8 + b;
        if (bitIdx < bits.length) {
          val = (val << 1) | bits[bitIdx];
        }
      }
      bytes[i] = val;
    }

    return RawCodewords(
      bytes: bytes,
      version: version,
      level: level,
    );
  }

  @override
  void placeFormatInfo({
    required QrMatrix matrix,
    required FormatInfo formatInfo,
  }) {
    final size = matrix.size;
    final formatBits = formatInfo.bits15;

    for (var i = 0; i < 15; i++) {
      final isDark = ((formatBits >> (14 - i)) & 1) == 1;

      // Top-Left placement
      final (x1, y1) = _formatPosTopLeft(i);
      matrix.setDark(x1, y1, dark: isDark);

      // Split placement (Bottom-Left and Top-Right)
      final (x2, y2) = _formatPosSplit(i, size);
      matrix.setDark(x2, y2, dark: isDark);
    }
  }

  @override
  FormatInfo readFormatInfo(QrMatrix matrix) {
    final size = matrix.size;

    // Read top-left
    var bitsTopLeft = 0;
    for (var i = 0; i < 15; i++) {
      final (x, y) = _formatPosTopLeft(i);
      bitsTopLeft = (bitsTopLeft << 1) | (matrix.isDark(x, y) ? 1 : 0);
    }

    // Read split
    var bitsSplit = 0;
    for (var i = 0; i < 15; i++) {
      final (x, y) = _formatPosSplit(i, size);
      bitsSplit = (bitsSplit << 1) | (matrix.isDark(x, y) ? 1 : 0);
    }

    try {
      return formatCodec.decode(bitsTopLeft);
    } catch (_) {
      return formatCodec.decode(bitsSplit);
    }
  }

  @override
  void placeVersionInfo({
    required QrMatrix matrix,
    required VersionInfo versionInfo,
  }) {
    final size = matrix.size;
    final bits18 = versionInfo.bits18;

    for (var i = 0; i < 18; i++) {
      final isDark = ((bits18 >> i) & 1) == 1;
      final row = i ~/ 3;
      final col = i % 3;

      // Bottom-Left (6x3): x in 0..5, y in size-11..size-9
      matrix.setDark(row, size - 11 + col, dark: isDark);

      // Top-Right (3x6): x in size-11..size-9, y in 0..5
      matrix.setDark(size - 11 + col, row, dark: isDark);
    }
  }

  @override
  VersionInfo? readVersionInfo(QrMatrix matrix, int matrixSize) {
    final vNum = (matrixSize - 17) ~/ 4;
    if (vNum < 7) return null;

    // Read Bottom-Left
    var bitsBL = 0;
    for (var i = 0; i < 18; i++) {
      final row = i ~/ 3;
      final col = i % 3;
      if (matrix.isDark(row, matrixSize - 11 + col)) {
        bitsBL |= (1 << i);
      }
    }

    // Read Top-Right
    var bitsTR = 0;
    for (var i = 0; i < 18; i++) {
      final row = i ~/ 3;
      final col = i % 3;
      if (matrix.isDark(matrixSize - 11 + col, row)) {
        bitsTR |= (1 << i);
      }
    }

    try {
      return versionCodec.decode(bitsBL);
    } catch (_) {
      return versionCodec.decode(bitsTR);
    }
  }

  void _placeFinderAndSeparator(QrMatrix matrix, ModuleRegistry registry, int x0, int y0) {
    // 7x7 finder pattern + 1 module light separator
    for (var dy = -1; dy <= 7; dy++) {
      for (var dx = -1; dx <= 7; dx++) {
        final x = x0 + dx;
        final y = y0 + dy;
        if (x < 0 || x >= matrix.size || y < 0 || y >= matrix.size) continue;

        registry.reserve(x, y);

        if (dx >= 0 && dx < 7 && dy >= 0 && dy < 7) {
          // Inside 7x7 Finder
          if (dx == 0 || dx == 6 || dy == 0 || dy == 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4)) {
            matrix.setDark(x, y, dark: true);
          } else {
            matrix.setDark(x, y, dark: false);
          }
        } else {
          // Separator
          matrix.setDark(x, y, dark: false);
        }
      }
    }
  }

  void _placeAlignmentPattern(QrMatrix matrix, ModuleRegistry registry, int cx, int cy) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final x = cx + dx;
        final y = cy + dy;
        registry.reserve(x, y);

        if (dx.abs() == 2 || dy.abs() == 2 || (dx == 0 && dy == 0)) {
          matrix.setDark(x, y, dark: true);
        } else {
          matrix.setDark(x, y, dark: false);
        }
      }
    }
  }

  bool _overlapsFinder(int cx, int cy, int size) {
    // Finders occupy [0..7, 0..7], [size-8..size-1, 0..7], [0..7, size-8..size-1]
    if (cx <= 8 && cy <= 8) return true; // Top-Left
    if (cx >= size - 9 && cy <= 8) return true; // Top-Right
    if (cx <= 8 && cy >= size - 9) return true; // Bottom-Left
    return false;
  }

  void _reserveFormatAreas(ModuleRegistry registry, int size) {
    for (var i = 0; i < 15; i++) {
      final (x1, y1) = _formatPosTopLeft(i);
      registry.reserve(x1, y1);
      final (x2, y2) = _formatPosSplit(i, size);
      registry.reserve(x2, y2);
    }
  }

  void _reserveVersionAreas(ModuleRegistry registry, int size) {
    // Bottom-Left (6x3)
    registry.reserveRect(0, size - 11, 6, 3);
    // Top-Right (3x6)
    registry.reserveRect(size - 11, 0, 3, 6);
  }

  static (int, int) _formatPosTopLeft(int index) {
    if (index <= 5) return (index, 8);
    if (index == 6) return (7, 8);
    if (index == 7) return (8, 8);
    if (index == 8) return (8, 7);
    return (8, 14 - index);
  }

  static (int, int) _formatPosSplit(int index, int size) {
    if (index <= 6) return (8, size - 1 - index);
    return (size - 15 + index, 8);
  }
}
