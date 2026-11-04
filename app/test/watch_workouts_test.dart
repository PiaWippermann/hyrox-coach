import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_coach/watch_workouts.dart';

void main() {
  test('Intervalllauf wird mit Aufwärmen, Wiederholungen, Pace und Trabpause übersetzt', () {
    final plan = {
      'weeks': [
        {
          'days': [
            {
              'date': '2026-11-05',
              'dayType': 'run',
              'title': 'Intervalle',
              'variants': [
                {
                  'location': 'gym',
                  'blocks': [
                    {'name': 'Ein', 'type': 'warmup', 'exercises': [{'name': 'Einlaufen', 'station': 'run', 'durationSec': 600, 'targetPace': '6:30/km'}]},
                    {'name': 'Haupt', 'type': 'main', 'exercises': [
                      {'name': 'Intervall', 'station': 'run', 'sets': 5, 'distanceM': 1000, 'targetPace': '5:00/km', 'restSec': 90},
                      {'name': 'Liegestütze', 'reps': 10},
                    ]},
                    {'name': 'Aus', 'type': 'cooldown', 'exercises': [{'name': 'Auslaufen', 'station': 'run', 'durationSec': 300, 'targetPace': '7:00/km'}]},
                  ],
                }
              ],
            },
            {'date': '2026-11-06', 'dayType': 'strength', 'title': 'Kraft', 'variants': []},
          ],
        }
      ],
    };
    final items = WatchWorkouts.buildItems(plan, {}, DateTime(2026, 11, 4));
    expect(items, hasLength(1));
    final w = items.single;
    expect(w['warmup'], {'durationSec': 600});
    expect(w['cooldown'], {'durationSec': 300});
    expect(w['blocks'], [
      {'iterations': 5, 'work': {'distanceM': 1000.0, 'paceSecPerKm': 300}, 'recoverySec': 90},
    ]);
    // erledigte Läufe werden nicht übertragen
    expect(WatchWorkouts.buildItems(plan, {'2026-11-05|Intervalle'}, DateTime(2026, 11, 4)), isEmpty);
  });
}
