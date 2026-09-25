import 'package:test/test.dart';
import 'package:two_level_qr/two_level_qr.dart';

void main() {
  group('BitStreamCodec', () {
    const codec = BitStreamCodec();

    test('encodes and decodes numeric segment', () {
      final segments = [Segment.numeric('01234567')];
      final version = QrVersion(1);
      final dataCodewords = codec.encodeSegments(
        segments: segments,
        version: version,
        level: ErrorCorrectionLevel.medium,
      );

      final decodedSegments = codec.decodeDataCodewords(
        dataCodewords: dataCodewords.bytes,
        version: version,
      );

      expect(decodedSegments.length, equals(1));
      expect(decodedSegments[0].mode, equals(Mode.numeric));
      expect(decodedSegments[0].text, equals('01234567'));
    });

    test('encodes and decodes alphanumeric segment', () {
      final segments = [Segment.alphanumeric('HELLO 123%')];
      final version = QrVersion(1);
      final dataCodewords = codec.encodeSegments(
        segments: segments,
        version: version,
        level: ErrorCorrectionLevel.medium,
      );

      final decodedSegments = codec.decodeDataCodewords(
        dataCodewords: dataCodewords.bytes,
        version: version,
      );

      expect(decodedSegments.length, equals(1));
      expect(decodedSegments[0].mode, equals(Mode.alphanumeric));
      expect(decodedSegments[0].text, equals('HELLO 123%'));
    });

    test('encodes and decodes byte segment', () {
      final segments = [Segment.byteFromUtf8('TwoLevelQR is clean! 🚀')];
      final version = QrVersion(2);
      final dataCodewords = codec.encodeSegments(
        segments: segments,
        version: version,
        level: ErrorCorrectionLevel.medium,
      );

      final decodedSegments = codec.decodeDataCodewords(
        dataCodewords: dataCodewords.bytes,
        version: version,
      );

      expect(decodedSegments.length, equals(1));
      expect(decodedSegments[0].mode, equals(Mode.byte));
    });
  });

  group('BlockInterleaver', () {
    const interleaver = BlockInterleaver();
    final rsCodec = ReedSolomonCodec();

    test('interleaves and deinterleaves v1-M (single block)', () {
      const bitStreamCodec = BitStreamCodec();
      final version = QrVersion(1);
      final data = bitStreamCodec.encodeSegments(
        segments: [Segment.alphanumeric('HELLO WORLD')],
        version: version,
        level: ErrorCorrectionLevel.medium,
      );

      final finalCodewords = interleaver.interleave(
        dataCodewords: data,
        version: version,
        level: ErrorCorrectionLevel.medium,
        rsCodec: rsCodec,
      );

      expect(finalCodewords.bytes.length, equals(26));
      expect(finalCodewords.remainderBitsCount, equals(0));

      final rawCodewords = RawCodewords(
        bytes: finalCodewords.bytes,
        version: version,
        level: ErrorCorrectionLevel.medium,
      );

      final blocks = interleaver.deinterleave(
        rawCodewords: rawCodewords,
        version: version,
        level: ErrorCorrectionLevel.medium,
      );

      expect(blocks.length, equals(1));
      expect(blocks[0].dataCodewords, equals(data.bytes));
    });

    test('interleaves and deinterleaves multi-block v5-H (4 blocks: 2 of 11, 2 of 12)', () {
      final version = QrVersion(5);
      final totalDataLen = dataCodewordsCapacity(5, ErrorCorrectionLevel.high); // 44 bytes
      final dummyData = List.generate(totalDataLen, (i) => (i * 7 + 3) & 0xFF);

      final dataCodewords = DataCodewords(
        bytes: dummyData,
        version: version,
        level: ErrorCorrectionLevel.high,
      );

      final finalCodewords = interleaver.interleave(
        dataCodewords: dataCodewords,
        version: version,
        level: ErrorCorrectionLevel.high,
        rsCodec: rsCodec,
      );

      final rawCodewords = RawCodewords(
        bytes: finalCodewords.bytes,
        version: version,
        level: ErrorCorrectionLevel.high,
      );

      final blocks = interleaver.deinterleave(
        rawCodewords: rawCodewords,
        version: version,
        level: ErrorCorrectionLevel.high,
      );

      expect(blocks.length, equals(4));
      final reconstructedData = blocks.expand((b) => b.dataCodewords).toList();
      expect(reconstructedData, equals(dummyData));
    });
  });
}
