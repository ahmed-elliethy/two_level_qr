import 'dart:typed_data';

/// Parses a hex string, ignoring whitespace and ':' separators.
Uint8List hex(String s) {
  final clean = s.replaceAll(RegExp(r'[\s:]'), '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
