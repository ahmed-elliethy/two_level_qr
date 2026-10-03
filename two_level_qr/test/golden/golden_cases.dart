import 'package:two_level_qr/two_level_qr.dart';

/// Shared, platform-independent computation of the hidden-channel golden
/// values. Used by `schedule_golden_test.dart` and by the one-off script that
/// generated `schedule_golden_data.dart` from the 0.1.x implementation.
///
/// Digests use a 32-bit rolling hash that is exact on both the VM and JS.
int digest(Iterable<int> values) {
  var h = 0x811C9DC5;
  for (final v in values) {
    h = ((h ^ (v & 0xFFFF)) * 31 + (v >> 16)) & 0x3FFFFFFF;
  }
  return h;
}

const goldenKeys = ['my-secret-key', '', 'κλειδί-🔑', 'k'];
const goldenRatios = [0.3, 0.5, 0.8, 1.0];
const goldenVersions = [1, 5, 10, 25, 40];

/// Returns `{caseName: [count, digest, first up to 8 (block,pos) pairs...]}`
/// for every key x ratio x version x level schedule, plus matrix digests for a
/// handful of full plaintext two-level encodes.
Map<String, List<int>> computeGolden() {
  final out = <String, List<int>>{};
  final encoder = EncodeQr();
  for (final v in goldenVersions) {
    for (final level in ErrorCorrectionLevel.values) {
      final blocks = encoder
          .execute(text: 'golden', level: level, explicitVersion: v)
          .rsBlocks;
      for (final key in goldenKeys) {
        for (final ratio in goldenRatios) {
          final s = KeyedErrorScheduler(key: key, ratio: ratio);
          final count = s.computeCapacity(blocks).totalBytes;
          final pos = s.schedulePositions(blocks: blocks, count: count);
          final flat = <int>[
            for (final p in pos) ...[p.blockIndex, p.position],
          ];
          out['sched v$v ${level.label} r${ratio.toStringAsFixed(1)} "$key"'] = [
            count,
            digest(flat),
            ...flat.take(16),
          ];
        }
      }
    }
  }

  const encodes = [
    ('https://example.com/public-info', 'SECRET_KEY_12345', 'my-secret-key', 0.8),
    ('HELLO 123', 'héllo wörld ✓', 'abc', 0.5),
    ('1234567890', '', 'k', 1.0),
  ];
  for (final level in ErrorCorrectionLevel.values) {
    for (final (pub, hidden, key, ratio) in encodes) {
      final enc = TwoLevelQr.encodeWithHiddenMessage(
        publicText: pub,
        hiddenText: hidden,
        key: key,
        ratio: ratio,
        level: level,
      );
      final m = enc.matrix;
      final bits = <int>[
        for (var y = 0; y < m.size; y++)
          for (var x = 0; x < m.size; x++) m.isDark(x, y) ? 1 : 0,
      ];
      out['encode ${level.label} "$pub" "$hidden" "$key" r${ratio.toStringAsFixed(1)}'] = [
        enc.version.number,
        enc.maskPattern.bits,
        digest(bits),
      ];
    }
  }
  return out;
}
