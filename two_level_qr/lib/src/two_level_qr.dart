import 'dart:convert';

import 'data/ciphers/aes_siv.dart';
import 'data/ciphers/passphrase_kdf.dart';
import 'decode_result.dart';
import 'domain/corrected_codewords.dart';
import 'domain/data_codewords.dart';
import 'domain/error_correction_level.dart';
import 'domain/final_codewords.dart';
import 'domain/format_info.dart';
import 'domain/hidden_cipher.dart';
import 'domain/hidden_message.dart';
import 'domain/mask_pattern.dart';
import 'domain/mode.dart';
import 'domain/qr_matrix.dart';
import 'domain/raw_codewords.dart';
import 'domain/rs_block.dart';
import 'domain/segment.dart';
import 'domain/version.dart';
import 'domain/version_info.dart';
import 'encode_result.dart';
import 'usecases/decode_encrypted_hidden_qr.dart';
import 'usecases/decode_hidden_qr.dart';
import 'usecases/decode_qr.dart';
import 'usecases/encode_encrypted_hidden_qr.dart';
import 'usecases/encode_hidden_qr.dart';
import 'usecases/hidden_envelope.dart';
import 'usecases/encode_qr.dart';

/// TwoLevelQR main SDK facade.
///
/// Provides high-level encode/decode APIs and direct access to call and inspect
/// any individual stage in the encode and decode pipelines.
class TwoLevelQr {
  TwoLevelQr({
    EncodeQr? encodeQr,
    DecodeQr? decodeQr,
    EncodeHiddenQr? encodeHiddenQr,
    DecodeHiddenQr? decodeHiddenQr,
    EncodeEncryptedHiddenQr? encodeEncryptedHiddenQr,
    DecodeEncryptedHiddenQr? decodeEncryptedHiddenQr,
  })  : _encodeQr = encodeQr ?? EncodeQr(),
        _decodeQr = decodeQr ?? DecodeQr(),
        _encodeHiddenQr = encodeHiddenQr ?? EncodeHiddenQr(),
        _decodeHiddenQr = decodeHiddenQr ?? DecodeHiddenQr(),
        _encodeEncryptedHiddenQr =
            encodeEncryptedHiddenQr ?? EncodeEncryptedHiddenQr(),
        _decodeEncryptedHiddenQr =
            decodeEncryptedHiddenQr ?? DecodeEncryptedHiddenQr();

  final EncodeQr _encodeQr;
  final DecodeQr _decodeQr;
  final EncodeHiddenQr _encodeHiddenQr;
  final DecodeHiddenQr _decodeHiddenQr;
  final EncodeEncryptedHiddenQr _encodeEncryptedHiddenQr;
  final DecodeEncryptedHiddenQr _decodeEncryptedHiddenQr;

  /// Default singleton instance.
  static final TwoLevelQr instance = TwoLevelQr();

  // ===========================================================================
  // High-Level Public APIs
  // ===========================================================================

  /// Encodes [text] into a complete [EncodeResult] containing the QR Matrix and all intermediate checkpoints.
  static EncodeResult encode(
    String text, {
    List<Segment>? segments,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.medium,
    int? explicitVersion,
    MaskPattern? explicitMask,
  }) =>
      instance._encodeQr.execute(
        text: text,
        segments: segments,
        level: level,
        explicitVersion: explicitVersion,
        explicitMask: explicitMask,
      );

  /// Decodes a [QrMatrix] into a complete [DecodeResult] containing the decoded text, error-correction details, and inspectable checkpoints.
  static DecodeResult decode(QrMatrix matrix) =>
      instance._decodeQr.execute(matrix);

  /// Encodes [publicText] as the normal QR payload and hides [hiddenText]
  /// inside the Reed-Solomon error channel using [key].
  ///
  /// [key] is the *position key*: it only decides where the hidden bytes
  /// go. The bytes themselves are not encrypted, and anyone who runs
  /// Reed-Solomon correction can see them (in scrambled order). Use
  /// [encodeWithEncryptedHiddenMessage] when the hidden message must stay
  /// confidential.
  ///
  /// See [HiddenEncodeOptions] for the configurable [ratio] (default `0.8`).
  static EncodeResult encodeWithHiddenMessage({
    required String publicText,
    required String hiddenText,
    required String key,
    double ratio = 0.8,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
    int? explicitVersion,
    MaskPattern? explicitMask,
  }) {
    return instance._encodeHiddenQr.execute(
      publicText: publicText,
      hiddenText: hiddenText,
      options: HiddenEncodeOptions(key: key, ratio: ratio),
      level: level,
      explicitVersion: explicitVersion,
      explicitMask: explicitMask,
    );
  }

  /// Decodes a two-level QR [matrix] and extracts the hidden message with [key].
  ///
  /// If [key] is incorrect, the returned [HiddenDecodeResult.hiddenBytes] and
  /// [HiddenDecodeResult.hiddenText] contain garbage rather than the original
  /// secret. The [ratio] must match the value used during encoding.
  static HiddenDecodeResult decodeWithHiddenMessage(
    QrMatrix matrix, {
    required String key,
    double ratio = 0.8,
  }) {
    return instance._decodeHiddenQr.execute(
      matrix,
      key: key,
      ratio: ratio,
    );
  }

  /// Encodes [publicText] as the normal QR payload and hides [hiddenText],
  /// encrypted with [cipher], inside the Reed-Solomon error channel.
  ///
  /// * [positionKey] decides *where* the hidden bytes go (like `key` in
  ///   [encodeWithHiddenMessage]).
  /// * [encryptionPassphrase] protects *what* they say. It must differ from
  ///   [positionKey].
  /// * [cipher] defaults to [AesSivCipher]. Its scheme ID is written into
  ///   the QR so the receiver knows which cipher to use.
  /// * [ratio] limits the hidden errors per block exactly as in plaintext
  ///   mode; the length prefix, scheme byte and cipher overhead all count
  ///   against it. See [hiddenMessageCapacity].
  /// * [kdfIterations] sets the PBKDF2 iteration count of the default
  ///   cipher (default [PassphraseKdf.defaultIterations]). It is ignored when
  ///   [cipher] is given; configure that cipher directly instead. The decoder
  ///   must use the same value.
  static EncodeResult encodeWithEncryptedHiddenMessage({
    required String publicText,
    required String hiddenText,
    required String positionKey,
    required String encryptionPassphrase,
    HiddenMessageCipher? cipher,
    int kdfIterations = PassphraseKdf.defaultIterations,
    double ratio = 0.8,
    ErrorCorrectionLevel level = ErrorCorrectionLevel.high,
    int? explicitVersion,
    MaskPattern? explicitMask,
  }) {
    return instance._encodeEncryptedHiddenQr.execute(
      publicText: publicText,
      hiddenText: hiddenText,
      positionKey: positionKey,
      encryptionPassphrase: encryptionPassphrase,
      cipher: cipher ?? AesSivCipher(iterations: kdfIterations),
      ratio: ratio,
      level: level,
      explicitVersion: explicitVersion,
      explicitMask: explicitMask,
    );
  }

  /// Decodes a two-level QR [matrix] and decrypts its hidden message.
  ///
  /// [positionKey], [encryptionPassphrase] and [ratio] must match the
  /// encoder. [ciphers] lists the accepted schemes; the scheme ID stored in
  /// the QR picks one of them. By default the built-in AES-SIV and (on
  /// native platforms) ChaCha20-Poly1305 ciphers are accepted, configured
  /// with [kdfIterations], which must match the encoder's value.
  ///
  /// Throws a [HiddenMessageCryptoException] on any failure and never falls
  /// back to plaintext.
  static EncryptedHiddenDecodeResult decodeWithEncryptedHiddenMessage(
    QrMatrix matrix, {
    required String positionKey,
    required String encryptionPassphrase,
    double ratio = 0.8,
    List<HiddenMessageCipher>? ciphers,
    int kdfIterations = PassphraseKdf.defaultIterations,
  }) {
    return instance._decodeEncryptedHiddenQr.execute(
      matrix,
      positionKey: positionKey,
      encryptionPassphrase: encryptionPassphrase,
      ratio: ratio,
      ciphers:
          ciphers ?? HiddenEnvelope.defaultCiphers(iterations: kdfIterations),
    );
  }

  /// Largest hidden message, in UTF-8 bytes, that fits in a QR of [version]
  /// and [level] at [ratio].
  ///
  /// With [cipher] `null` this is plaintext mode (channel capacity minus the
  /// 2-byte length prefix). With a cipher it also subtracts the scheme byte
  /// and `cipher.overhead`.
  static int hiddenMessageCapacity({
    required int version,
    required ErrorCorrectionLevel level,
    double ratio = 0.8,
    HiddenMessageCipher? cipher,
  }) {
    if (version < 1 || version > 40) {
      throw RangeError.range(version, 1, 40, 'version');
    }
    if (!(ratio > 0.0 && ratio <= 1.0)) {
      throw ArgumentError.value(ratio, 'ratio', 'must be in (0.0, 1.0]');
    }
    return HiddenEnvelope.messageCapacity(
      version: version,
      level: level,
      ratio: ratio,
      cipher: cipher,
    );
  }

  // ===========================================================================
  // ENCODE PIPELINE: Stage-by-Stage Methods
  // ENCODE: text → segments → dataCodewords → RS ecc → interleave → finalCodewords → place+mask → matrix
  // ===========================================================================

  /// Stage 1: text → segments
  static List<Segment> stage1SegmentText(String text) =>
      EncodeQr.autoSegment(text);

  /// Stage 2: segments → dataCodewords
  static DataCodewords stage2EncodeDataCodewords({
    required List<Segment> segments,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) =>
      instance._encodeQr.bitStreamCodec.encodeSegments(
        segments: segments,
        version: version,
        level: level,
      );

  /// Stage 3: dataCodewords → RS ecc blocks
  static List<RsBlock> stage3GenerateRsBlocks({
    required DataCodewords dataCodewords,
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

    final blocks = <RsBlock>[];
    var offset = 0;
    for (var b = 0; b < totalBlocks; b++) {
      final len = (b < count1) ? data1 : data2;
      final blockData = dataCodewords.bytes.sublist(offset, offset + len);
      offset += len;
      final ecc = instance._encodeQr.rsCodec.generateEcc(
        data: blockData,
        eccCodewordsCount: ecPer,
      );
      blocks.add(RsBlock(
          blockIndex: b, dataCodewords: blockData, eccCodewords: ecc.bytes));
    }
    return blocks;
  }

  /// Stage 4: RS blocks → interleave → finalCodewords
  static FinalCodewords stage4InterleaveBlocks({
    required DataCodewords dataCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) =>
      instance._encodeQr.blockInterleaver.interleave(
        dataCodewords: dataCodewords,
        version: version,
        level: level,
        rsCodec: instance._encodeQr.rsCodec,
      );

  /// Stage 5: finalCodewords → place+mask → matrix
  static ({
    QrMatrix matrix,
    MaskPattern maskPattern,
    FormatInfo formatInfo,
    VersionInfo? versionInfo
  }) stage5PlaceAndMaskMatrix({
    required FinalCodewords finalCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
    MaskPattern? explicitMask,
  }) {
    final base_ = instance._encodeQr.matrixRenderer.createBaseMatrix(version);
    instance._encodeQr.matrixRenderer.placeData(
      matrix: base_.matrix,
      registry: base_.registry,
      finalCodewords: finalCodewords,
    );

    VersionInfo? versionInfo;
    if (version.number >= 7) {
      versionInfo = instance._encodeQr.versionCodec.encode(version);
      instance._encodeQr.matrixRenderer.placeVersionInfo(
        matrix: base_.matrix,
        versionInfo: versionInfo,
      );
    }

    final maskPattern = explicitMask ??
        instance._encodeQr.masking.pickBestMask(
          baseMatrix: base_.matrix,
          registry: base_.registry,
          version: version,
          level: level,
        );

    instance._encodeQr.masking.applyMask(
      matrix: base_.matrix,
      registry: base_.registry,
      pattern: maskPattern,
    );

    final formatInfo =
        instance._encodeQr.formatCodec.encode(level, maskPattern);
    instance._encodeQr.matrixRenderer.placeFormatInfo(
      matrix: base_.matrix,
      formatInfo: formatInfo,
    );

    return (
      matrix: base_.matrix,
      maskPattern: maskPattern,
      formatInfo: formatInfo,
      versionInfo: versionInfo,
    );
  }

  // ===========================================================================
  // DECODE PIPELINE: Stage-by-Stage Methods
  // DECODE: matrix → unmask → rawCodewords → deinterleave → RS decode → correctedCodewords → segments → text
  // ===========================================================================

  /// Stage 1: matrix → unmask (reads format/version info and reverses mask)
  static ({
    FormatInfo formatInfo,
    VersionInfo? versionInfo,
    QrMatrix unmaskedMatrix,
    QrVersion version
  }) stage1UnmaskMatrix(QrMatrix matrix) {
    final size = matrix.size;
    if (size < 21 || (size - 17) % 4 != 0) {
      throw FormatException('Invalid QR matrix dimension: ${size}x$size');
    }

    final vNum = (size - 17) ~/ 4;
    var version = QrVersion(vNum);

    final formatInfo = instance._decodeQr.matrixRenderer.readFormatInfo(matrix);
    final versionInfo =
        instance._decodeQr.matrixRenderer.readVersionInfo(matrix, size);
    if (versionInfo != null) {
      version = versionInfo.version;
    }

    final base_ = instance._decodeQr.matrixRenderer.createBaseMatrix(version);
    final unmasked = matrix.clone();
    instance._decodeQr.masking.applyMask(
      matrix: unmasked,
      registry: base_.registry,
      pattern: formatInfo.maskPattern,
    );

    return (
      formatInfo: formatInfo,
      versionInfo: versionInfo,
      unmaskedMatrix: unmasked,
      version: version,
    );
  }

  /// Stage 2: unmasked matrix → rawCodewords (extracts data bits from zig-zag track)
  static RawCodewords stage2ExtractRawCodewords({
    required QrMatrix unmaskedMatrix,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) {
    final base_ = instance._decodeQr.matrixRenderer.createBaseMatrix(version);
    return instance._decodeQr.matrixRenderer.extractData(
      matrix: unmaskedMatrix,
      registry: base_.registry,
      version: version,
      level: level,
    );
  }

  /// Stage 3: rawCodewords → deinterleave (reconstructs individual raw RS blocks WITH errors)
  static List<RsBlock> stage3DeinterleaveRawCodewords({
    required RawCodewords rawCodewords,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) =>
      instance._decodeQr.blockInterleaver.deinterleave(
        rawCodewords: rawCodewords,
        version: version,
        level: level,
      );

  /// Stage 4: raw RS blocks → RS decode → correctedCodewords (detects & corrects errors)
  static CorrectedCodewords stage4CorrectRsBlocks({
    required List<RsBlock> rawBlocks,
    required QrVersion version,
    required ErrorCorrectionLevel level,
  }) {
    final ecPer = ecCodewordsPerBlock(version.number, level);
    var totalErrors = 0;
    final correctedDataList = <int>[];
    final correctedBlocks = <RsBlock>[];

    for (var b = 0; b < rawBlocks.length; b++) {
      final rawBlock = rawBlocks[b];
      final received = rawBlock.fullBlock;

      final result = instance._decodeQr.rsCodec.correctBlock(
        received: received,
        dataCodewordsCount: rawBlock.dataCodewords.length,
        eccCodewordsCount: ecPer,
      );

      totalErrors += result.errorsCorrected;
      correctedDataList.addAll(result.data);

      correctedBlocks.add(RsBlock(
        blockIndex: b,
        dataCodewords: result.data,
        eccCodewords: rawBlock.eccCodewords,
      ));
    }

    return CorrectedCodewords(
      dataCodewords: correctedDataList,
      errorsCorrected: totalErrors,
      blocks: correctedBlocks,
    );
  }

  /// Stage 5: correctedCodewords → segments (parses mode indicators & payloads)
  static List<Segment> stage5DecodeSegments({
    required List<int> dataCodewords,
    required QrVersion version,
  }) =>
      instance._decodeQr.bitStreamCodec.decodeDataCodewords(
        dataCodewords: dataCodewords,
        version: version,
      );

  /// Stage 6: segments → text (reconstructs decoded string)
  static String stage6SegmentsToText(List<Segment> segments) {
    final textBuffer = StringBuffer();
    for (final s in segments) {
      if (s.mode == Mode.byte) {
        textBuffer.write(utf8.decode(s.bytes!, allowMalformed: true));
      } else if (s.text != null) {
        textBuffer.write(s.text);
      }
    }
    return textBuffer.toString();
  }
}
