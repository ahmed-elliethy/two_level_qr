import 'package:test/test.dart';

import 'golden_cases.dart';
import 'schedule_golden_data.dart';

/// Guards that the keyed position schedule (and therefore every plaintext
/// two-level QR) is bit-identical to 0.1.x on every platform, including JS.
void main() {
  test('hidden-channel schedules and plaintext encodes match 0.1.x golden', () {
    final actual = computeGolden();
    expect(actual.keys.toSet(), equals(scheduleGolden.keys.toSet()));
    for (final entry in scheduleGolden.entries) {
      expect(actual[entry.key], equals(entry.value), reason: entry.key);
    }
  });
}
