import 'dart:io';
import 'package:two_level_qr/two_level_qr.dart';
import '../terminal_utils.dart';

/// Performance benchmarking suite for TwoLevelQR encode and decode pipelines.
class BenchmarkRunner {
  BenchmarkRunner._();

  static void runBenchmarks({int warmup = 50, int iterations = 500}) {
    TerminalUtils.printHeader(
      'TwoLevelQR Performance Benchmarks',
      subtitle: 'Measuring pipeline latency and throughput ($iterations iterations)',
    );

    _benchScenario(
      name: 'Small Payload (v1-M): "HELLO WORLD"',
      text: 'HELLO WORLD',
      level: ErrorCorrectionLevel.medium,
      warmup: warmup,
      iterations: iterations,
    );

    _benchScenario(
      name: 'Medium Payload (v4-M): JSON Data',
      text: '{"user_id":10042,"action":"AUTHENTICATE","token":"abc123xyz789","ts":1774351234}',
      level: ErrorCorrectionLevel.medium,
      warmup: warmup,
      iterations: iterations,
    );

    _benchScenario(
      name: 'Large Payload (v10-H): URL with High Error Correction',
      text: 'https://github.com/two_level_qr/core/blob/master/benchmarks/reports/summary_q2_2026_performance_profile.dart?view=full_details#L120-L450',
      level: ErrorCorrectionLevel.high,
      warmup: warmup,
      iterations: iterations,
    );

    stdout.writeln();
  }

  static void _benchScenario({
    required String name,
    required String text,
    required ErrorCorrectionLevel level,
    required int warmup,
    required int iterations,
  }) {
    TerminalUtils.printSection(name);

    // Warmup
    for (var i = 0; i < warmup; i++) {
      final enc = TwoLevelQr.encode(text, level: level);
      TwoLevelQr.decode(enc.matrix);
    }

    // Benchmark Encode
    final encSw = Stopwatch()..start();
    EncodeResult? lastEnc;
    for (var i = 0; i < iterations; i++) {
      lastEnc = TwoLevelQr.encode(text, level: level);
    }
    encSw.stop();

    final encTotalUs = encSw.elapsedMicroseconds;
    final encAvgUs = encTotalUs / iterations;
    final encOpsPerSec = (iterations * 1000000) / encTotalUs;

    // Benchmark Decode
    final matrix = lastEnc!.matrix;
    final decSw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      TwoLevelQr.decode(matrix);
    }
    decSw.stop();

    final decTotalUs = decSw.elapsedMicroseconds;
    final decAvgUs = decTotalUs / iterations;
    final decOpsPerSec = (iterations * 1000000) / decTotalUs;

    TerminalUtils.printMetric('Version & Matrix Size', 'v${lastEnc.version.number} (${lastEnc.matrix.size}x${lastEnc.matrix.size})');
    TerminalUtils.printMetric('Encode Latency', '${encAvgUs.toStringAsFixed(2)} µs / op');
    TerminalUtils.printMetric('Encode Throughput', '${encOpsPerSec.toStringAsFixed(0)} ops / sec');
    TerminalUtils.printMetric('Decode Latency', '${decAvgUs.toStringAsFixed(2)} µs / op');
    TerminalUtils.printMetric('Decode Throughput', '${decOpsPerSec.toStringAsFixed(0)} ops / sec');
  }
}
