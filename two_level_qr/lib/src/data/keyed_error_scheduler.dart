import 'dart:convert';

import '../domain/rs_block.dart';

/// A scheduled error position inside a single RS block.
class HiddenErrorPosition {
  const HiddenErrorPosition({
    required this.blockIndex,
    required this.position,
  });

  /// Index of the RS block.
  final int blockIndex;

  /// Index inside the RS block's data codewords.
  ///
  /// The scheduler deliberately avoids ECC positions because the decoder only
  /// receives corrected data bytes; ECC bytes are left as received.
  final int position;

  @override
  String toString() => 'HiddenErrorPosition(block=$blockIndex, pos=$position)';
}

/// Capacity of the hidden channel for a given block layout.
class HiddenCapacity {
  const HiddenCapacity({
    required this.totalBytes,
    required this.errorsPerBlock,
  });

  /// Total number of secret bytes that can be embedded.
  final int totalBytes;

  /// Per-block usable error budget. Each entry is the number of byte errors
  /// that may be safely injected into the corresponding block.
  final List<int> errorsPerBlock;

  @override
  String toString() =>
      'HiddenCapacity(total=$totalBytes, perBlock=$errorsPerBlock)';
}

/// Schedules deterministic, key-dependent positions inside the Reed-Solomon
/// codewords where hidden bytes will be embedded.
///
/// The scheduler is fully self-contained: it uses a 64-bit keyed hash
/// (FNV-1a) to seed a 64-bit xorshift* PRNG, with no external dependencies.
class KeyedErrorScheduler {
  /// Creates a scheduler for the given [key] and [ratio].
  ///
  /// [ratio] is a fraction of the per-block error budget `t` (where
  /// `t = ecCodewordsPerBlock ~/ 2`). The resulting usable count is capped
  /// at `t - 1` so that at least one byte-error margin remains for noise.
  KeyedErrorScheduler({
    required this.key,
    this.ratio = 0.8,
  }) : assert(ratio > 0.0 && ratio <= 1.0, 'ratio must be in (0.0, 1.0]');

  final String key;
  final double ratio;

  /// Computes how many hidden bytes can safely be embedded in [blocks].
  ///
  /// Hidden bytes are injected only into data codeword positions, because the
  /// decoder only receives corrected data bytes; ECC bytes are left as received.
  /// The usable count per block is therefore capped at the data codeword count.
  HiddenCapacity computeCapacity(List<RsBlock> blocks) {
    final perBlock = <int>[];
    var total = 0;
    for (final block in blocks) {
      final ecPer = block.eccCodewords.length;
      final t = ecPer ~/ 2;
      final errorBudget = t <= 1 ? 0 : _min(t - 1, (t * ratio).floor());
      final usable = _min(block.dataCodewords.length, errorBudget);
      perBlock.add(usable);
      total += usable;
    }
    return HiddenCapacity(totalBytes: total, errorsPerBlock: perBlock);
  }

  /// Returns [count] distinct error positions distributed across [blocks]
  /// according to the per-block capacity.
  ///
  /// Positions are picked deterministically from the key and block index, so
  /// the same inputs always produce the same schedule. The order of the
  /// returned positions is the order in which hidden bytes are embedded and
  /// extracted.
  List<HiddenErrorPosition> schedulePositions({
    required List<RsBlock> blocks,
    required int count,
  }) {
    if (count == 0) return const [];

    final capacity = computeCapacity(blocks);
    if (count > capacity.totalBytes) {
      throw ArgumentError(
        'Hidden message requires $count byte positions, but capacity is only '
        '${capacity.totalBytes} for the selected QR version/level.',
      );
    }

    final remaining = List<int>.from(capacity.errorsPerBlock);
    final prngs = List<_Prng?>.generate(blocks.length, (b) {
      if (remaining[b] > 0) {
        final seed = _deriveBlockSeed(key, b, ratio);
        return _Prng(seed);
      }
      return null;
    });

    final positions = <HiddenErrorPosition>[];
    final usedPerBlock = List<Set<int>>.generate(blocks.length, (_) => <int>{});

    // Round-robin across blocks until we have scheduled [count] positions.
    while (positions.length < count) {
      for (var b = 0; b < blocks.length && positions.length < count; b++) {
        if (remaining[b] <= 0) continue;

        final dataLength = blocks[b].dataCodewords.length;
        final prng = prngs[b]!;
        var pos = -1;
        var attempts = 0;
        const maxAttempts = 10000;
        do {
          pos = prng.nextInt(dataLength);
          attempts++;
          if (attempts > maxAttempts) {
            throw StateError(
              'Unable to find a fresh error position in block $b '
              '(dataLength=$dataLength).',
            );
          }
        } while (usedPerBlock[b].contains(pos));

        usedPerBlock[b].add(pos);
        remaining[b]--;
        positions.add(HiddenErrorPosition(blockIndex: b, position: pos));
      }
    }

    return positions;
  }

  /// Derives a 64-bit seed from the key, ratio, and block index using FNV-1a.
  ///
  /// Including [ratio] in the seed ensures that two schedules with the same
  /// key but different ratios produce independent position sequences.
  static int _deriveBlockSeed(String key, int blockIndex, double ratio) {
    final salt = 'two_level_qr_hidden_channel';
    final ratioString = ratio.toStringAsFixed(6);
    final bytes = utf8.encode('$salt\x00$key\x00$ratioString\x00$blockIndex');
    return _fnv1a64(bytes);
  }

  /// FNV-1a 64-bit hash.
  static int _fnv1a64(List<int> data) {
    const fnvOffset = 0xcbf29ce484222325;
    const fnvPrime = 0x100000001b3;
    var hash = fnvOffset;
    for (final byte in data) {
      hash ^= byte & 0xFF;
      hash = _mask64(hash * fnvPrime);
    }
    return hash == 0 ? fnvOffset : hash;
  }

  static int _mask64(int value) => value & 0xFFFFFFFFFFFFFFFF;

  static int _min(int a, int b) => a < b ? a : b;
}

/// 64-bit xorshift* pseudo-random number generator.
///
/// Based on the variant by Sebastiano Vigna:
/// `x ^= x >> 12; x ^= x << 25; x ^= x >> 27; return x * 0x2545F4914F6CDD1D;`
class _Prng {
  _Prng(int seed) : _state = seed == 0 ? 1 : (seed & 0xFFFFFFFFFFFFFFFF);

  int _state;

  /// Returns a 32-bit unsigned integer in `[0, 2^32)`.
  int nextInt(int? maxExclusive) {
    var x = _state;
    x ^= x >>> 12;
    x ^= x << 25;
    x ^= x >>> 27;
    x = x & 0xFFFFFFFFFFFFFFFF;
    _state = x;
    final value = (x * 0x2545F4914F6CDD1D) & 0xFFFFFFFF;
    if (maxExclusive == null || maxExclusive <= 0) return value;
    return value % maxExclusive;
  }
}
