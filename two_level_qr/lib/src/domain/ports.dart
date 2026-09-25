import 'bit_buffer.dart';
import 'data_codewords.dart';
import 'ecc_codewords.dart';
import 'error_correction_level.dart';
import 'final_codewords.dart';
import 'format_info.dart';
import 'mask_pattern.dart';
import 'qr_matrix.dart';
import 'raw_codewords.dart';
import 'rs_block.dart';
import 'segment.dart';
import 'version.dart';
import 'version_info.dart';

/// Port for bit stream encoding and decoding.
abstract class BitStreamCodecPort {
  /// Encodes [segments] into a [BitBuffer] for [version] and [level], adding
  /// terminator and padding up to [dataCapacityBytes].
  DataCodewords encodeSegments({
    required List<Segment> segments,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  });

  /// Decodes [dataCodewords] back into the sequence of [Segment]s.
  List<Segment> decodeDataCodewords({
    required List<int> dataCodewords,
    required QrVersion version,
  });
}

/// Port for Reed-Solomon error correction encoding and decoding.
abstract class ReedSolomonCodecPort {
  /// Generates [eccCodewordsCount] ECC bytes for given [data].
  EccCodewords generateEcc({
    required List<int> data,
    required int eccCodewordsCount,
  });

  /// Corrects errors in a single RS block of [received] codewords (data + ECC).
  /// Returns the corrected data codewords and the count of corrected errors.
  ({List<int> data, int errorsCorrected}) correctBlock({
    required List<int> received,
    required int dataCodewordsCount,
    required int eccCodewordsCount,
  });
}

/// Port for splitting, interleaving, and de-interleaving RS blocks.
abstract class BlockInterleaverPort {
  /// Splits data into blocks, computes ECC, and interleaves to produce [FinalCodewords].
  FinalCodewords interleave({
    required DataCodewords dataCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
    required ReedSolomonCodecPort rsCodec,
  });

  /// De-interleaves raw codewords extracted from the matrix into individual RS blocks.
  List<RsBlock> deinterleave({
    required RawCodewords rawCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  });

  /// Interleaves already-constructed [blocks] into a [FinalCodewords] stream.
  ///
  /// This is useful when blocks have been deliberately modified (for example,
  /// to inject a hidden message into the error channel) after their ECC bytes
  /// were originally computed.
  FinalCodewords interleaveBlocks({
    required List<RsBlock> blocks,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  });
}

/// Port for matrix masking and penalty evaluation.
abstract class MaskingPort {
  /// Applies [pattern] to [matrix], flipping unreserved modules.
  void applyMask({
    required QrMatrix matrix,
    required ModuleRegistry registry,
    required MaskPattern pattern,
  });

  /// Evaluates the ISO/IEC 18004 penalty score ($N_1 + N_2 + N_3 + N_4$) for [matrix].
  int calculatePenalty(QrMatrix matrix);

  /// Evaluates all 8 mask patterns and returns the one with lowest penalty.
  MaskPattern pickBestMask({
    required QrMatrix baseMatrix,
    required ModuleRegistry registry,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  });
}

/// Port for rendering module layouts, placing data, and reading data from matrices.
abstract class MatrixRendererPort {
  /// Creates the base matrix with function patterns and reserved regions.
  ({QrMatrix matrix, ModuleRegistry registry}) createBaseMatrix(QrVersion version);

  /// Places data bits into the matrix along the standard 2-module zig-zag track.
  void placeData({
    required QrMatrix matrix,
    required ModuleRegistry registry,
    required FinalCodewords finalCodewords,
  });

  /// Reads raw data bits from unreserved modules in the matrix.
  RawCodewords extractData({
    required QrMatrix matrix,
    required ModuleRegistry registry,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  });

  /// Places format information at both standard locations.
  void placeFormatInfo({
    required QrMatrix matrix,
    required FormatInfo formatInfo,
  });

  /// Reads and decodes format info from the matrix.
  FormatInfo readFormatInfo(QrMatrix matrix);

  /// Places version information (versions >= 7).
  void placeVersionInfo({
    required QrMatrix matrix,
    required VersionInfo versionInfo,
  });

  /// Reads and decodes version info from the matrix (versions >= 7).
  VersionInfo? readVersionInfo(QrMatrix matrix, int matrixSize);
}

/// Port for Format Information encoding, decoding, and error correction.
abstract class FormatInfoCodecPort {
  FormatInfo encode(ErrorCorrectionLevel level, MaskPattern maskPattern);
  FormatInfo decode(int formatBits);
}

/// Port for Version Information encoding, decoding, and error correction.
abstract class VersionInfoCodecPort {
  VersionInfo encode(QrVersion version);
  VersionInfo decode(int versionBits);
}
