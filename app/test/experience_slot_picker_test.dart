import 'package:flutter_test/flutter_test.dart';
import 'package:vita/features/chat/experience_slot_picker.dart';

void main() {
  test(
      'server slots are parsed in UTC; malformed, expired and duplicate times are removed',
      () {
    final slots = parseExperienceSlots({
      'server_time': '2026-10-13T07:00:00Z',
      'slots': [
        {
          'starts_at': '2026-10-13T15:30:00+08:00',
          'ends_at': '2026-10-13T16:30:00+08:00'
        },
        {
          'starts_at': '2026-10-13T07:30:00Z',
          'ends_at': '2026-10-13T08:30:00Z'
        },
        {'starts_at': 'invalid', 'ends_at': 'invalid'},
        {
          'starts_at': '2026-10-13T07:01:00Z',
          'ends_at': '2026-10-13T08:01:00Z'
        },
      ]
    });
    expect(slots.length, 1);
    expect(slots.single.start, DateTime.utc(2026, 10, 13, 7, 30));
    expect(slots.single.end.difference(slots.single.start),
        const Duration(hours: 1));
  });
}
