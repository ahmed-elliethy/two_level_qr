import 'mode.dart';

/// One encoded chunk of the message — a checkpoint value between `text` and
/// `dataCodewords`. A message is a list of [Segment]s, each with its own mode.
class Segment {
  const Segment._(this.mode, this.text, this.bytes);

  /// Numeric segment: characters must all be `0-9`.
  factory Segment.numeric(String digits) {
    for (final cu in digits.codeUnits) {
      if (cu < 0x30 || cu > 0x39) {
        throw ArgumentError.value(
            digits, 'digits', 'numeric segments allow only 0-9');
      }
    }
    return Segment._(Mode.numeric, digits, null);
  }

  /// Alphanumeric segment over the 45-char set.
  factory Segment.alphanumeric(String text) {
    for (var i = 0; i < text.length; i++) {
      if (alphanumericValue(text[i]) == null) {
        throw ArgumentError.value(
            text, 'text', 'illegal alphanumeric char "${text[i]}" at $i');
      }
    }
    return Segment._(Mode.alphanumeric, text, null);
  }

  /// Byte segment from raw bytes (callers typically pass UTF-8).
  factory Segment.byte(List<int> bytes) =>
      Segment._(Mode.byte, null, List<int>.unmodifiable(bytes));

  /// Byte segment from a string encoded as UTF-8.
  factory Segment.byteFromUtf8(String text) =>
      Segment.byte(utf8Encode(text));

  /// Kanji segment (input assumed to be representable in Shift-JIS).
  factory Segment.kanji(String text) =>
      Segment._(Mode.kanji, text, null);

  final Mode mode;

  /// Original text, when applicable (null for raw-byte segments).
  final String? text;

  /// Raw payload bytes for [Mode.byte] segments.
  final List<int>? bytes;

  /// Number of *characters* counted by the character-count indicator.
  int get characterCount {
    switch (mode) {
      case Mode.byte:
        return bytes!.length;
      default:
        return text!.length;
    }
  }

  @override
  String toString() => 'Segment(${mode.name}, count=$characterCount)';
}

/// The QR alphanumeric character set, in index order (§6.4.4, Table 2).
const String kAlphanumericCharset =
    r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

/// Returns the 0..44 value of [char], or null if not in the set.
int? alphanumericValue(String char) {
  final idx = kAlphanumericCharset.indexOf(char);
  return idx < 0 ? null : idx;
}

/// Minimal UTF-8 encoder kept here so the domain layer has no `dart:convert`
/// dependency drift; produces the byte list for [text].
List<int> utf8Encode(String text) {
  final units = text.runes.toList();
  final out = <int>[];
  for (final rune in units) {
    if (rune < 0x80) {
      out.add(rune);
    } else if (rune < 0x800) {
      out.add(0xC0 | (rune >> 6));
      out.add(0x80 | (rune & 0x3F));
    } else if (rune < 0x10000) {
      out.add(0xE0 | (rune >> 12));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    } else {
      out.add(0xF0 | (rune >> 18));
      out.add(0x80 | ((rune >> 12) & 0x3F));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    }
  }
  return out;
}
