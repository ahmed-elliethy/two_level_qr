import '../domain/bit_buffer.dart';
import '../domain/data_codewords.dart';
import '../domain/error_correction_level.dart';
import '../domain/mode.dart';
import '../domain/ports.dart';
import '../domain/segment.dart';
import '../domain/version.dart';

/// Encodes segment payloads into data codewords and decodes data codewords back to segments.
class BitStreamCodec implements BitStreamCodecPort {
  const BitStreamCodec();

  @override
  DataCodewords encodeSegments({
    required List<Segment> segments,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) {
    final buffer = BitBuffer();
    final vNum = version.number;
    final totalCapacity = dataCodewordsCapacity(vNum, level);
    final totalBitCapacity = totalCapacity * 8;

    for (final segment in segments) {
      // 1. Mode indicator (4 bits)
      buffer.appendBits(segment.mode.bits, 4);

      // 2. Character count indicator
      final countBits = segment.mode.charCountBits(vNum);
      if (countBits > 0) {
        buffer.appendBits(segment.characterCount, countBits);
      }

      // 3. Payload bits
      switch (segment.mode) {
        case Mode.numeric:
          _writeNumeric(buffer, segment.text!);
          break;
        case Mode.alphanumeric:
          _writeAlphanumeric(buffer, segment.text!);
          break;
        case Mode.byte:
          _writeByte(buffer, segment.bytes!);
          break;
        case Mode.kanji:
          _writeKanji(buffer, segment.text!);
          break;
        case Mode.eci:
        case Mode.terminator:
          break;
      }
    }

    if (buffer.length > totalBitCapacity) {
      throw ArgumentError(
        'Data overflow: payload required ${buffer.length} bits, but capacity is $totalBitCapacity bits for v$vNum-${level.label}',
      );
    }

    // 4. Terminator (up to 4 bits of zeros)
    final terminatorBits = (totalBitCapacity - buffer.length).clamp(0, 4);
    if (terminatorBits > 0) {
      buffer.appendBits(0, terminatorBits);
    }

    // 5. Pad to byte boundary
    buffer.padToByteBoundary();

    // 6. Pad bytes (alternate 0xEC and 0x11)
    final bytesNeeded = totalCapacity - buffer.byteLength;
    for (var i = 0; i < bytesNeeded; i++) {
      buffer.appendBits((i % 2 == 0) ? 0xEC : 0x11, 8);
    }

    return DataCodewords(
      bytes: buffer.toBytes().toList(),
      version: version,
      level: level,
    );
  }

  @override
  List<Segment> decodeDataCodewords({
    required List<int> dataCodewords,
    required QrVersion version,
  }) {
    final bitList = <int>[];
    for (final b in dataCodewords) {
      for (var i = 7; i >= 0; i--) {
        bitList.add((b >> i) & 1);
      }
    }

    final segments = <Segment>[];
    var offset = 0;
    final vNum = version.number;

    int readBits(int numBits) {
      if (offset + numBits > bitList.length) {
        throw FormatException('Unexpected end of bit stream');
      }
      var val = 0;
      for (var i = 0; i < numBits; i++) {
        val = (val << 1) | bitList[offset++];
      }
      return val;
    }

    while (offset + 4 <= bitList.length) {
      final modeBits = readBits(4);
      if (modeBits == Mode.terminator.bits) {
        break; // Reached terminator
      }

      Mode? mode;
      for (final m in Mode.values) {
        if (m.bits == modeBits && m != Mode.terminator) {
          mode = m;
          break;
        }
      }

      if (mode == null) {
        break; // Unrecognized mode or trailing padding bits
      }

      final countBits = mode.charCountBits(vNum);
      if (offset + countBits > bitList.length) break;
      final charCount = readBits(countBits);

      switch (mode) {
        case Mode.numeric:
          final sb = StringBuffer();
          var remaining = charCount;
          while (remaining >= 3) {
            final val = readBits(10);
            sb.write(val.toString().padLeft(3, '0'));
            remaining -= 3;
          }
          if (remaining == 2) {
            final val = readBits(7);
            sb.write(val.toString().padLeft(2, '0'));
          } else if (remaining == 1) {
            final val = readBits(4);
            sb.write(val.toString());
          }
          segments.add(Segment.numeric(sb.toString()));
          break;

        case Mode.alphanumeric:
          final sb = StringBuffer();
          var remaining = charCount;
          while (remaining >= 2) {
            final val = readBits(11);
            final c1 = val ~/ 45;
            final c2 = val % 45;
            sb.write(kAlphanumericCharset[c1]);
            sb.write(kAlphanumericCharset[c2]);
            remaining -= 2;
          }
          if (remaining == 1) {
            final val = readBits(6);
            sb.write(kAlphanumericCharset[val]);
          }
          segments.add(Segment.alphanumeric(sb.toString()));
          break;

        case Mode.byte:
          final bytes = <int>[];
          for (var i = 0; i < charCount; i++) {
            bytes.add(readBits(8));
          }
          segments.add(Segment.byte(bytes));
          break;

        case Mode.kanji:
          // Read 13 bits per double-byte character
          final bytes = <int>[];
          for (var i = 0; i < charCount; i++) {
            final val = readBits(13);
            var assembled = ((val ~/ 0xC0) << 8) | (val % 0xC0);
            if (assembled + 0x8140 <= 0x9FFC) {
              assembled += 0x8140;
            } else {
              assembled += 0xC140;
            }
            bytes.add((assembled >> 8) & 0xFF);
            bytes.add(assembled & 0xFF);
          }
          segments.add(Segment.byte(bytes));
          break;

        case Mode.eci:
        case Mode.terminator:
          break;
      }
    }

    return segments;
  }

  void _writeNumeric(BitBuffer buffer, String digits) {
    var i = 0;
    while (i + 3 <= digits.length) {
      final chunk = int.parse(digits.substring(i, i + 3));
      buffer.appendBits(chunk, 10);
      i += 3;
    }
    if (digits.length - i == 2) {
      final chunk = int.parse(digits.substring(i, i + 2));
      buffer.appendBits(chunk, 7);
    } else if (digits.length - i == 1) {
      final chunk = int.parse(digits.substring(i, i + 1));
      buffer.appendBits(chunk, 4);
    }
  }

  void _writeAlphanumeric(BitBuffer buffer, String text) {
    var i = 0;
    while (i + 2 <= text.length) {
      final v1 = alphanumericValue(text[i])!;
      final v2 = alphanumericValue(text[i + 1])!;
      buffer.appendBits(v1 * 45 + v2, 11);
      i += 2;
    }
    if (text.length - i == 1) {
      final v = alphanumericValue(text[i])!;
      buffer.appendBits(v, 6);
    }
  }

  void _writeByte(BitBuffer buffer, List<int> bytes) {
    for (final b in bytes) {
      buffer.appendBits(b, 8);
    }
  }

  void _writeKanji(BitBuffer buffer, String text) {
    // Expect raw Shift-JIS bytes in text or encode
    final codeUnits = text.codeUnits;
    for (final cu in codeUnits) {
      var val = cu;
      if (val >= 0x8140 && val <= 0x9FFC) {
        val -= 0x8140;
      } else if (val >= 0xE040 && val <= 0xEAA4) {
        val -= 0xC140;
      }
      final encoded = ((val >> 8) * 0xC0) + (val & 0xFF);
      buffer.appendBits(encoded, 13);
    }
  }
}
