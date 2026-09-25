import '../domain/bit_buffer.dart';
import '../domain/data_codewords.dart';
import '../domain/error_correction_level.dart';
import '../domain/final_codewords.dart';
import '../domain/ports.dart';
import '../domain/raw_codewords.dart';
import '../domain/rs_block.dart';
import '../domain/version.dart';

/// Handles splitting data into RS blocks, computing ECC, and interleaving / de-interleaving.
class BlockInterleaver implements BlockInterleaverPort {
  const BlockInterleaver();

  @override
  FinalCodewords interleave({
    required DataCodewords dataCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
    required ReedSolomonCodecPort rsCodec,
  }) {
    final vNum = version.number;
    final structure = blockStructure(vNum, level);
    final count1 = structure[0];
    final data1 = structure[1];
    final count2 = structure[2];
    final data2 = structure[3];
    final totalBlocks = count1 + count2;
    final ecPer = ecCodewordsPerBlock(vNum, level);

    // 1. Split data into RS blocks and compute ECC
    final blocks = <RsBlock>[];
    var dataOffset = 0;

    for (var b = 0; b < totalBlocks; b++) {
      final blockDataLen = (b < count1) ? data1 : data2;
      final blockData = dataCodewords.bytes.sublist(dataOffset, dataOffset + blockDataLen);
      dataOffset += blockDataLen;

      final ecc = rsCodec.generateEcc(
        data: blockData,
        eccCodewordsCount: ecPer,
      );

      blocks.add(RsBlock(
        blockIndex: b,
        dataCodewords: blockData,
        eccCodewords: ecc.bytes,
      ));
    }

    // 2. Interleave data codewords across all blocks
    final maxDataLen = count2 > 0 ? data2 : data1;
    final interleavedBytes = <int>[];

    for (var i = 0; i < maxDataLen; i++) {
      for (var b = 0; b < totalBlocks; b++) {
        if (i < blocks[b].dataCodewords.length) {
          interleavedBytes.add(blocks[b].dataCodewords[i]);
        }
      }
    }

    // 3. Interleave ECC codewords across all blocks
    for (var i = 0; i < ecPer; i++) {
      for (var b = 0; b < totalBlocks; b++) {
        interleavedBytes.add(blocks[b].eccCodewords[i]);
      }
    }

    // 4. Build bit buffer with interleaved bytes and trailing remainder bits
    final bitBuffer = BitBuffer();
    for (final byte in interleavedBytes) {
      bitBuffer.appendBits(byte, 8);
    }
    final rem = version.remainderBits;
    if (rem > 0) {
      bitBuffer.appendBits(0, rem);
    }

    return FinalCodewords(
      bytes: interleavedBytes,
      remainderBitsCount: rem,
      bitBuffer: bitBuffer,
    );
  }

  @override
  List<RsBlock> deinterleave({
    required RawCodewords rawCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) {
    final vNum = version.number;
    final structure = blockStructure(vNum, level);
    final count1 = structure[0];
    final data1 = structure[1];
    final count2 = structure[2];
    final data2 = structure[3];
    final totalBlocks = count1 + count2;
    final ecPer = ecCodewordsPerBlock(vNum, level);

    final blockDataLists = List.generate(totalBlocks, (_) => <int>[]);
    final blockEccLists = List.generate(totalBlocks, (_) => <int>[]);

    final maxDataLen = count2 > 0 ? data2 : data1;
    var rawOffset = 0;

    // 1. De-interleave data codewords
    for (var i = 0; i < maxDataLen; i++) {
      for (var b = 0; b < totalBlocks; b++) {
        final blockTargetLen = (b < count1) ? data1 : data2;
        if (i < blockTargetLen) {
          if (rawOffset >= rawCodewords.length) {
            throw FormatException('Truncated raw codewords during data de-interleaving');
          }
          blockDataLists[b].add(rawCodewords[rawOffset++]);
        }
      }
    }

    // 2. De-interleave ECC codewords
    for (var i = 0; i < ecPer; i++) {
      for (var b = 0; b < totalBlocks; b++) {
        if (rawOffset >= rawCodewords.length) {
          throw FormatException('Truncated raw codewords during ECC de-interleaving');
        }
        blockEccLists[b].add(rawCodewords[rawOffset++]);
      }
    }

    // Assemble RsBlock objects
    return List.generate(totalBlocks, (b) {
      return RsBlock(
        blockIndex: b,
        dataCodewords: blockDataLists[b],
        eccCodewords: blockEccLists[b],
      );
    });
  }

  @override
  FinalCodewords interleaveBlocks({
    required List<RsBlock> blocks,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) {
    final vNum = version.number;
    final structure = blockStructure(vNum, level);
    final count1 = structure[0];
    final count2 = structure[2];
    final totalBlocks = count1 + count2;
    final ecPer = ecCodewordsPerBlock(vNum, level);

    if (blocks.length != totalBlocks) {
      throw ArgumentError(
        'Expected $totalBlocks RS blocks for v$vNum-${level.label}, '
        'got ${blocks.length}',
      );
    }

    final maxDataLen = count2 > 0 ? blocks.last.dataCodewords.length : blocks.first.dataCodewords.length;
    final interleavedBytes = <int>[];

    // 1. Interleave data codewords across all blocks
    for (var i = 0; i < maxDataLen; i++) {
      for (var b = 0; b < totalBlocks; b++) {
        if (i < blocks[b].dataCodewords.length) {
          interleavedBytes.add(blocks[b].dataCodewords[i]);
        }
      }
    }

    // 2. Interleave ECC codewords across all blocks
    for (var i = 0; i < ecPer; i++) {
      for (var b = 0; b < totalBlocks; b++) {
        interleavedBytes.add(blocks[b].eccCodewords[i]);
      }
    }

    // 3. Build bit buffer with interleaved bytes and trailing remainder bits
    final bitBuffer = BitBuffer();
    for (final byte in interleavedBytes) {
      bitBuffer.appendBits(byte, 8);
    }
    final rem = version.remainderBits;
    if (rem > 0) {
      bitBuffer.appendBits(0, rem);
    }

    return FinalCodewords(
      bytes: interleavedBytes,
      remainderBitsCount: rem,
      bitBuffer: bitBuffer,
    );
  }
}
