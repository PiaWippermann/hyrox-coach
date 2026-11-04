import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_coach/util.dart';

void main() {
  final anamnese = {
    'schedule': {
      'fixedSessions': [
        {'weekday': 1, 'time': '20:00', 'title': 'Yoga / Mobility', 'dayType': 'recovery'},
        {'weekday': 3, 'time': '19:15', 'title': 'Hyrox-Kurs', 'dayType': 'hyrox_sim'},
      ],
    },
  };
  Map<String, dynamic> day(String date, String type, String title) => {'date': date, 'dayType': type, 'title': title};

  test('Alte Plantage mit Kursnamen gelten als Duplikat des festen Termins', () {
    expect(isFixedDuplicate(anamnese, day('2026-11-04', 'mixed', 'Hyrox-Kurs (abends)')), isTrue); // Mittwoch
    expect(isFixedDuplicate(anamnese, day('2026-11-11', 'mixed', 'Hyrox-Kurs (abends, locker)')), isTrue);
    expect(isFixedDuplicate(anamnese, day('2026-11-09', 'recovery', 'Yoga (abends)')), isTrue); // Montag
  });

  test('Echtes Training am Kurstag oder ähnliche Titel bleiben sichtbar', () {
    expect(isFixedDuplicate(anamnese, day('2026-11-04', 'hyrox_sim', 'Hyrox-Teilsimulation 6 Runden')), isFalse);
    expect(isFixedDuplicate(anamnese, day('2026-11-02', 'run', 'Lockerer Lauf + Aktivierung')), isFalse);
    expect(isFixedDuplicate(anamnese, day('2026-11-05', 'mixed', 'Hyrox-Kurs (abends)')), isFalse); // Donnerstag: kein Kurs
    expect(isFixedDuplicate(anamnese, day('2026-11-11', 'rest', 'Ruhetag (Hyrox-Kurs abends)')), isFalse);
  });
}
