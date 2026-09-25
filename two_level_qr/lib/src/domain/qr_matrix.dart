/// An immutable-ish square grid of QR modules (true = dark).
///
/// This is the value passed between the "place + mask" stage and every
/// downstream consumer (rendering, decoding). It knows nothing about QR
/// semantics beyond geometry — reserved-region bookkeeping lives in
/// [ModuleRegistry].
class QrMatrix {
  QrMatrix._(this._size, this._dark);

  final int _size;

  /// Flat row-major storage, index = y * size + x.
  final List<bool> _dark;

  factory QrMatrix.allDark(int size) =>
      QrMatrix._(size, List<bool>.filled(size * size, true));

  factory QrMatrix.allLight(int size) =>
      QrMatrix._(size, List<bool>.filled(size * size, false));

  int get size => _size;

  bool operator [](List<int> xy) => isDark(xy[0], xy[1]);

  bool isDark(int x, int y) {
    _checkBounds(x, y);
    return _dark[y * _size + x];
  }

  void setDark(int x, int y, {bool dark = true}) {
    _checkBounds(x, y);
    _dark[y * _size + x] = dark;
  }

  void toggle(int x, int y) {
    _checkBounds(x, y);
    _dark[y * _size + x] = !_dark[y * _size + x];
  }

  /// Deep copy.
  QrMatrix clone() => QrMatrix._(_size, List<bool>.from(_dark));

  /// Number of dark modules.
  int countDark() => _dark.where((d) => d).length;

  void _checkBounds(int x, int y) {
    if (x < 0 || x >= _size || y < 0 || y >= _size) {
      throw IndexOutOfBoundsException('($x,$y) outside ${_size}x$_size matrix');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is QrMatrix &&
      other._size == _size &&
      _listEquals(other._dark, _dark);

  @override
  int get hashCode => Object.hash(_size, Object.hashAll(_dark));

  static bool _listEquals(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// ASCII rendering (dark = `██`, light = `  `), useful for debugging/tests.
  @override
  String toString() {
    final sb = StringBuffer();
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        sb.write(_dark[y * _size + x] ? '██' : '  ');
      }
      sb.write('\n');
    }
    return sb.toString();
  }
}

/// Raised when a module coordinate falls outside the matrix.
class IndexOutOfBoundsException implements Exception {
  IndexOutOfBoundsException(this.message);
  final String message;
  @override
  String toString() => 'IndexOutOfBoundsException: $message';
}

/// Tracks which modules are occupied by function patterns or reserved areas so
/// that data placement never overwrites them.
class ModuleRegistry {
  ModuleRegistry(this.size)
      : _reserved = List<bool>.generate(
          size * size,
          (_) => false,
          growable: false,
        );

  final int size;
  final List<bool> _reserved;

  bool isReserved(int x, int y) {
    _check(x, y);
    return _reserved[y * size + x];
  }

  void reserve(int x, int y) {
    _check(x, y);
    _reserved[y * size + x] = true;
  }

  void reserveRect(int x0, int y0, int width, int height) {
    for (var dy = 0; dy < height; dy++) {
      for (var dx = 0; dx < width; dx++) {
        reserve(x0 + dx, y0 + dy);
      }
    }
  }

  int countFree() => _reserved.where((r) => !r).length;

  void _check(int x, int y) {
    if (x < 0 || x >= size || y < 0 || y >= size) {
      throw IndexOutOfBoundsException('($x,$y) outside ${size}x$size region');
    }
  }
}
