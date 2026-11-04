import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'util.dart';

/// Einstellungen für Erinnerungen (lokal auf dem Gerät).
class ReminderSettings {
  ReminderSettings({this.daily = true, this.dailyTime = '07:30', this.fixed = true, this.checkin = true, this.race = true});

  bool daily; // morgens: „Heute: …“
  String dailyTime; // HH:mm
  bool fixed; // nach einem festen Termin: abhaken?
  bool checkin; // Zwei-Wochen-Check-in fällig
  bool race; // Vorabend eines Rennens

  static Future<ReminderSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return ReminderSettings(
      daily: p.getBool('rem_daily') ?? true,
      dailyTime: p.getString('rem_daily_time') ?? '07:30',
      fixed: p.getBool('rem_fixed') ?? true,
      checkin: p.getBool('rem_checkin') ?? true,
      race: p.getBool('rem_race') ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('rem_daily', daily);
    await p.setString('rem_daily_time', dailyTime);
    await p.setBool('rem_fixed', fixed);
    await p.setBool('rem_checkin', checkin);
    await p.setBool('rem_race', race);
  }
}

/// Lokale Erinnerungen. Werden bei jeder Plan- oder Anamnese-Änderung für die nächsten 14 Tage neu geplant
/// (iOS erlaubt höchstens 64 ausstehende Benachrichtigungen).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    iOS: DarwinNotificationDetails(),
    android: AndroidNotificationDetails('reminders', 'Erinnerungen', channelDescription: 'Training, Kurse und Check-ins'),
  );

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Berechtigung erst anfragen, wenn wirklich etwas geplant wird
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  Future<bool> _requestPermission() async {
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true, badge: false);
    final android = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return ios ?? android ?? true;
  }

  /// Plant alle Erinnerungen neu. [checkinDue] = Zeitpunkt, ab dem der nächste Check-in fällig ist.
  Future<void> reschedule({
    required Map<String, dynamic>? plan,
    required Map<String, dynamic>? anamnese,
    required Set<String> doneKeys,
    required DateTime? checkinDue,
    DateTime? planEnd,
    bool hasUpcoming = false,
  }) async {
    try {
      await _init();
      await _plugin.cancelAll();
      final s = await ReminderSettings.load();
      if (!s.daily && !s.fixed && !s.checkin && !s.race) return;
      if (!await _requestPermission()) return;

      final now = tz.TZDateTime.now(tz.local);
      var id = 0;
      Future<void> at(DateTime when, String title, String body) async {
        final t = tz.TZDateTime.from(when, tz.local);
        if (!t.isAfter(now) || id >= 60) return;
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: t,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: title,
          body: body,
        );
      }

      DateTime clock(String date, String hhmm, {Duration plus = Duration.zero}) {
        final d = parseIso(date);
        final p = hhmm.split(':');
        return DateTime(d.year, d.month, d.day, int.tryParse(p.first) ?? 7, p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0)
            .add(plus);
      }

      final days = <String, Map<String, dynamic>>{
        for (final w in asMapList(plan?['weeks']))
          for (final d in asMapList(w['days'])) d['date'].toString(): d,
      };
      for (var i = 0; i < 14; i++) {
        final date = isoDate(DateTime.now().add(Duration(days: i)));
        final day = days[date];
        if (s.daily && day != null && day['dayType'] != 'rest' && day['dayType'] != 'race' &&
            !isFixedDuplicate(anamnese, day) &&
            !doneKeys.contains(doneKey(date, day['title']))) {
          await at(clock(date, s.dailyTime), 'Heute: ${day['title']}',
              '${dayTypeLabels[day['dayType']] ?? ''} · ${day['durationMin']} Min. Viel Spaß!');
        }
        if (s.fixed) {
          for (final f in fixedSessionsOn(anamnese, date)) {
            if (doneKeys.contains(doneKey(date, f['title']))) continue;
            final dur = (f['durationMin'] as num?)?.toInt() ?? 60;
            await at(clock(date, f['time'].toString(), plus: Duration(minutes: dur + 15)), '${f['title']} erledigt?',
                'Hak ihn in der App ab, damit er in deine Belastung einfließt.');
          }
        }
        if (s.race) {
          for (final r in racesOn(anamnese, isoDate(DateTime.now().add(Duration(days: i + 1))))) {
            await at(clock(date, '18:00'), 'Morgen: ${r['name']}',
                'Checkliste, Split-Plan und Aufwärmen findest du im Renntag-Modus. Viel Erfolg!');
          }
        }
      }
      if (planEnd != null && !hasUpcoming) {
        final ready = planEnd.subtract(const Duration(days: 2));
        await at(DateTime(ready.year, ready.month, ready.day, 18), 'Dein nächster Block ist fertig',
            'Der Coach hat ihn an deine Ergebnisse angepasst – schau rein, was sich ändert.');
      }
      if (s.checkin && checkinDue != null) {
        final due = checkinDue.isBefore(DateTime.now()) ? DateTime.now().add(const Duration(hours: 2)) : checkinDue;
        await at(DateTime(due.year, due.month, due.day, 18), 'Zeit für deinen Check-in',
            'Dein Coach wertet die letzten 2 Wochen aus und schlägt Anpassungen vor.');
      }
    } catch (_) {
      // Erinnerungen sind ein Extra – Fehler dürfen die App nicht stören
    }
  }
}
