// Unit tests for the pure presentation + model logic that enforces AccessAI's
// conservative-language and multi-person rules. These are deterministic and
// touch no network, plugins, or fonts, so they run fast under `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:accessai_mobile/core/format.dart';
import 'package:accessai_mobile/models/visitor_event.dart';

void main() {
  group('ageBand — age is only ever an approximate band, never a raw number',
      () {
    test('unknown / non-positive ages return empty', () {
      expect(ageBand(null), '');
      expect(ageBand(0), '');
      expect(ageBand(-4), '');
    });

    test('young children are hedged, not numbered', () {
      expect(ageBand(7), 'likely a child');
    });

    test('adults collapse to a decade band', () {
      expect(ageBand(24), 'likely in their twenties');
      expect(ageBand(29), 'likely in their twenties');
      expect(ageBand(41), 'likely in their forties');
    });

    test('never leaks the raw number', () {
      for (final a in [18, 33, 47, 62, 88]) {
        expect(ageBand(a).contains(a.toString()), isFalse,
            reason: 'ageBand($a) must not contain the digits');
      }
    });
  });

  group('hedgedExpression — expressions are always cautious', () {
    test('bare cue gains an "appears" hedge', () {
      expect(hedgedExpression('calm'), 'appears calm');
    });

    test('already-hedged cues are left as-is', () {
      expect(hedgedExpression('appears anxious'), 'appears anxious');
      expect(hedgedExpression('looks happy'), 'looks happy');
      expect(hedgedExpression('seems upset'), 'seems upset');
    });

    test('empty stays empty', () {
      expect(hedgedExpression('   '), '');
    });
  });

  group('modeLabel / modeShort', () {
    test('known modes map to their labels', () {
      expect(modeShort('blind'), 'Blind');
      expect(modeShort('deaf'), 'Deaf');
      expect(modeShort('both'), 'Both');
      expect(modeLabel('deaf'), 'Deaf — visual + vibration');
    });

    test('unknown mode falls back to Both', () {
      expect(modeShort('mystery'), 'Both');
    });
  });

  group('VisitorEvent.countLine — grammatical for 0 / 1 / many', () {
    VisitorEvent build(Map<String, dynamic> j) => VisitorEvent.fromJson(j);

    test('empty event reads "No one detected"', () {
      expect(build(<String, dynamic>{}).countLine, 'No one detected');
    });

    test('single known person', () {
      final e = build({
        'visitor_count': 1,
        'people': [
          {'known': true, 'name': 'Alex', 'is_spoof': false},
        ],
      });
      expect(e.countLine, '1 person — 1 known');
      expect(e.knownCount, 1);
      expect(e.unknownCount, 0);
    });

    test('mixed group breaks down known vs unknown', () {
      final e = build({
        'visitor_count': 3,
        'people': [
          {'known': true, 'name': 'Alex', 'is_spoof': false},
          {'known': false, 'name': 'Unknown', 'is_spoof': false},
          {'known': false, 'name': 'Unknown', 'is_spoof': false},
        ],
      });
      expect(e.countLine, '3 people — 1 known, 2 unknown');
    });

    test('a spoofed "known" person does not count as trusted-known', () {
      final e = build({
        'visitor_count': 1,
        'people': [
          {'known': true, 'name': 'Alex', 'is_spoof': true},
        ],
      });
      expect(e.knownCount, 0);
      expect(e.unknownCount, 1);
      expect(e.anySpoof, isTrue);
    });
  });

  group('VisitorEvent tolerates missing / partial fields', () {
    test('fromJson never throws on an empty map', () {
      final e = VisitorEvent.fromJson(<String, dynamic>{});
      expect(e.hazards, 'none');
      expect(e.people, isEmpty);
      expect(e.hasSpeech, isFalse);
      expect(e.reidId, isNull);
    });
  });
}
