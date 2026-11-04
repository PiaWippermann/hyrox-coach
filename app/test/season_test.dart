import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_coach/widgets/season_timeline.dart';

void main() {
  test('A-Rennen in ~13 Wochen: Aufbau → Spezifisch → Taper → Rennen → Regeneration, lückenlos', () {
    final s = Season.build({
      'goal': {
        'mode': 'race',
        'races': [
          {'name': 'Düsseldorf', 'date': '2026-11-14', 'priority': 'B'},
          {'name': 'Hamburg', 'date': '2027-02-05', 'priority': 'A'},
        ],
      },
    }, DateTime(2026, 11, 4));
    expect(s.phases.map((p) => p.label), ['Aufbau', 'Spezifisch', 'Taper', 'Rennen', 'Regeneration']);
    expect(s.peak, DateTime(2027, 2, 5));
    expect(s.start, DateTime(2026, 11, 2)); // Montag dieser Woche
    for (var i = 1; i < s.phases.length; i++) {
      expect(s.phases[i].start, s.phases[i - 1].end.add(const Duration(days: 1)), reason: 'Lücke vor ${s.phases[i].label}');
    }
    expect(s.title, contains('Hamburg'));
  });

  test('Offenes Ziel: 4-Wochen-Zyklen', () {
    final s = Season.build({'goal': {'mode': 'open'}}, DateTime(2026, 11, 4));
    expect(s.phases.take(2).map((p) => (p.label, p.days)), [('Aufbau', 21), ('Entlastung', 7)]);
  });
}
