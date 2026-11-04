import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../notifications.dart';
import '../state/app_state.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  ReminderSettings? _s;

  @override
  void initState() {
    super.initState();
    ReminderSettings.load().then((s) => mounted ? setState(() => _s = s) : null);
  }

  Future<void> _update(void Function(ReminderSettings) change) async {
    setState(() => change(_s!));
    await _s!.save();
    if (mounted) context.read<AppState>().rescheduleReminders();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('Erinnerungen')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              SwitchListTile(
                title: const Text('Training des Tages'),
                subtitle: Text('Morgens um ${s.dailyTime}: was heute ansteht'),
                value: s.daily,
                onChanged: (v) => _update((x) => x.daily = v),
              ),
              ListTile(
                enabled: s.daily,
                leading: const Icon(Icons.schedule),
                title: const Text('Uhrzeit'),
                trailing: Text(s.dailyTime),
                onTap: () async {
                  final p = s.dailyTime.split(':');
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
                  );
                  if (t != null) {
                    await _update((x) => x.dailyTime =
                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  }
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Feste Termine abhaken'),
                subtitle: const Text('Kurz nach Ende eines Kurses, falls noch nicht abgehakt'),
                value: s.fixed,
                onChanged: (v) => _update((x) => x.fixed = v),
              ),
              SwitchListTile(
                title: const Text('Check-in alle 2 Wochen'),
                subtitle: const Text('Wenn der Coach-Check-in fällig ist'),
                value: s.checkin,
                onChanged: (v) => _update((x) => x.checkin = v),
              ),
              SwitchListTile(
                title: const Text('Vorabend eines Rennens'),
                subtitle: const Text('Hinweis auf Checkliste und Split-Plan'),
                value: s.race,
                onChanged: (v) => _update((x) => x.race = v),
              ),
            ]),
    );
  }
}
