import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// Test suite covering mathematical foundations, error-correction codecs, and pure services.
class MathAndCodecTests {
  MathAndCodecTests._();

  static int runAll() {
    TerminalUtils.printSection('Suite 1: Mathematical Foundations & Pure Services');
    var failures = 0;

    // 1. Galois Field GF(256)
    failures += _testGaloisField();

    // 2. Reed-Solomon Codec
    failures += _testReedSolomon();

    // 3. BCH Codec
    failures += _testBchCodec();

    // 4. Bit Stream Codec
    failures += _testBitStreamCodec();

    // 5. Block Interleaver
    failures += _testBlockInterleaver();

    // 6. Masking & Penalty Evaluation
    failures += _testMasking();

    // 7. Matrix Renderer
    failures += _testMatrixRenderer();

    return failures;
  }

  static int _testGaloisField() {
    var fails = 0;
    final gf = GaloisField256.instance;

    // Test 1: Inverses
    var invOk = true;
    for (var a = 1; a < 256; a++) {
      if (gf.multiply(a, gf.inverse(a)) != 1) {
        invOk = false;
        break;
      }
    }
    TerminalUtils.printTestResult('GaloisField256: Multiplicative Inverses (1..255)', invOk);
    if (!invOk) fails++;

    // Test 2: Division
    var divOk = true;
    for (var a = 1; a <= 20; a++) {
      for (var b = 1; b <= 20; b++) {
        if (gf.multiply(gf.divide(a, b), b) != a) {
          divOk = false;
          break;
        }
      }
    }
    TerminalUtils.printTestResult('GaloisField256: Field Division Consistency', divOk);
    if (!divOk) fails++;

    // Test 3: Generator Polynomials
    final g10 = gf.generatorPolynomial(10);
    final g10Ok = g10.length == 11 && g10[0] == 1;
    TerminalUtils.printTestResult('GaloisField256: RS Generator Polynomial (degree 10)', g10Ok);
    if (!g10Ok) fails++;

    return fails;
  }

  static int _testReedSolomon() {
    var fails = 0;
    final rs = ReedSolomonCodec();

    // Test 1: Generate ECC
    final data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17];
    final ecc = rs.generateEcc(data: data, eccCodewordsCount: 10);
    final eccOk = ecc.length == 10 && ecc.bytes[0] == 196 && ecc.bytes[9] == 23;
    TerminalUtils.printTestResult('ReedSolomonCodec: Systematic ECC Generation (10 bytes)', eccOk);
    if (!eccOk) fails++;

    // Test 2: Correct up to t errors (t = 5)
    final received = [...data, ...ecc.bytes];
    received[2] ^= 0x33;
    received[7] ^= 0x77;
    received[12] ^= 0xAA;
    received[18] ^= 0x55;
    received[22] ^= 0x11;

    final res = rs.correctBlock(
      received: received,
      dataCodewordsCount: data.length,
      eccCodewordsCount: 10,
    );
    final correctOk = res.errorsCorrected == 5 && _listEquals(res.data, data);
    TerminalUtils.printTestResult('ReedSolomonCodec: Correct 5/5 Codeword Errors (t=5)', correctOk);
    if (!correctOk) fails++;

    // Test 3: Reject > t errors
    received[0] ^= 0xFF; // 6th error
    var threw = false;
    try {
      rs.correctBlock(
        received: received,
        dataCodewordsCount: data.length,
        eccCodewordsCount: 10,
      );
    } catch (_) {
      threw = true;
    }
    TerminalUtils.printTestResult('ReedSolomonCodec: Uncorrectable Error Detection (6 > 5)', threw);
    if (!threw) fails++;

    return fails;
  }

  static int _testBchCodec() {
    var fails = 0;
    final formatCodec = FormatInfoCodec();
    final versionCodec = VersionInfoCodec();

    // Test 1: All 32 Format Combinations
    var allFormatsOk = true;
    for (final level in ErrorCorrectionLevel.values) {
      for (final mask in MaskPattern.values) {
        final enc = formatCodec.encode(level, mask);
        final dec = formatCodec.decode(enc.bits15);
        if (dec.level != level || dec.maskPattern != mask) {
          allFormatsOk = false;
          break;
        }
      }
    }
    TerminalUtils.printTestResult('BchCodec: 32/32 Format Information Combinations', allFormatsOk);
    if (!allFormatsOk) fails++;

    // Test 2: 3-bit Format Error Correction
    final original = formatCodec.encode(ErrorCorrectionLevel.quartile, MaskPattern.pattern3);
    final corruptedFormat = original.bits15 ^ 0x07; // flip 3 lowest bits
    final decFormat = formatCodec.decode(corruptedFormat);
    final formatCorrectionOk = decFormat.level == ErrorCorrectionLevel.quartile &&
        decFormat.maskPattern == MaskPattern.pattern3;
    TerminalUtils.printTestResult('BchCodec: BCH(15, 5) 3-Bit Error Recovery', formatCorrectionOk);
    if (!formatCorrectionOk) fails++;

    // Test 3: Version Info (v7..v40)
    var allVersionsOk = true;
    for (var v = 7; v <= 40; v++) {
      final enc = versionCodec.encode(QrVersion(v));
      final dec = versionCodec.decode(enc.bits18);
      if (dec.version.number != v) {
        allVersionsOk = false;
        break;
      }
    }
    TerminalUtils.printTestResult('BchCodec: Version Information 7..40 Verification', allVersionsOk);
    if (!allVersionsOk) fails++;

    return fails;
  }

  static int _testBitStreamCodec() {
    var fails = 0;
    const codec = BitStreamCodec();
    final version = QrVersion(1);

    // Test 1: Numeric
    final numSeg = [Segment.numeric('9876543210')];
    final numData = codec.encodeSegments(
      segments: numSeg,
      version: version,
      level: ErrorCorrectionLevel.medium,
    );
    final decNum = codec.decodeDataCodewords(dataCodewords: numData.bytes, version: version);
    final numOk = decNum.isNotEmpty && decNum[0].text == '9876543210';
    TerminalUtils.printTestResult('BitStreamCodec: Numeric Mode Encode/Decode', numOk);
    if (!numOk) fails++;

    // Test 2: Alphanumeric
    final alphaSeg = [Segment.alphanumeric(r'ABC 123 $%*')];
    final alphaData = codec.encodeSegments(
      segments: alphaSeg,
      version: version,
      level: ErrorCorrectionLevel.medium,
    );
    final decAlpha = codec.decodeDataCodewords(dataCodewords: alphaData.bytes, version: version);
    final alphaOk = decAlpha.isNotEmpty && decAlpha[0].text == r'ABC 123 $%*';
    TerminalUtils.printTestResult('BitStreamCodec: Alphanumeric Mode Encode/Decode', alphaOk);
    if (!alphaOk) fails++;

    // Test 3: Byte UTF-8
    final byteSeg = [Segment.byteFromUtf8('Hello QR 🌐')];
    final byteData = codec.encodeSegments(
      segments: byteSeg,
      version: version,
      level: ErrorCorrectionLevel.low,
    );
    final decByte = codec.decodeDataCodewords(dataCodewords: byteData.bytes, version: version);
    final byteOk = decByte.isNotEmpty && decByte[0].mode == Mode.byte;
    TerminalUtils.printTestResult('BitStreamCodec: UTF-8 Byte Mode Encode/Decode', byteOk);
    if (!byteOk) fails++;

    return fails;
  }

  static int _testBlockInterleaver() {
    var fails = 0;
    const interleaver = BlockInterleaver();
    final rsCodec = ReedSolomonCodec();

    // Multi-block v10-High test (8 blocks: 6 of 15, 2 of 16)
    final version = QrVersion(10);
    final cap = dataCodewordsCapacity(10, ErrorCorrectionLevel.high); // 122 bytes
    final dummyData = List.generate(cap, (i) => (i * 13 + 7) & 0xFF);

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

    final reconstructed = blocks.expand((b) => b.dataCodewords).toList();
    final interleaveOk = blocks.length == 8 && _listEquals(reconstructed, dummyData);
    TerminalUtils.printTestResult('BlockInterleaver: Multi-Block Interleave/De-interleave (v10-H 8 blocks)', interleaveOk);
    if (!interleaveOk) fails++;

    return fails;
  }

  static int _testMasking() {
    var fails = 0;
    const masking = Masking();
    final matrix = QrMatrix.allDark(21);
    final penalty = masking.calculatePenalty(matrix);
    final penaltyOk = penalty > 0;
    TerminalUtils.printTestResult('Masking: ISO/IEC 18004 Penalty Score Evaluation', penaltyOk, extra: 'Score: $penalty');
    if (!penaltyOk) fails++;

    return fails;
  }

  static int _testMatrixRenderer() {
    var fails = 0;
    const renderer = MatrixRenderer();
    final base = renderer.createBaseMatrix(QrVersion(1));
    final matrix = base.matrix;
    final registry = base.registry;

    // Check finders are reserved
    final findersOk = registry.isReserved(3, 3) &&
        registry.isReserved(17, 3) &&
        registry.isReserved(3, 17) &&
        matrix.isDark(3, 3); // Finder centers are dark
    TerminalUtils.printTestResult('MatrixRenderer: Finder Patterns & Reserved Geometry', findersOk);
    if (!findersOk) fails++;

    return fails;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
