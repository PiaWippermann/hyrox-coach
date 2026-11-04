import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../health_sync.dart';
import '../watch_workouts.dart';
import '../state/app_state.dart';
import '../util.dart';
import '../widgets/logo.dart';
import 'anamnese_screen.dart';
import 'chat_screen.dart';
import 'goal_screen.dart';
import 'reminder_settings_screen.dart';
import 'workout_screen.dart';
import 'plan_screen.dart';
import 'progress_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      const PlanScreen(),
      const ProgressScreen(),
      const _ProfileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          const LogoMark(size: 30),
          const SizedBox(width: 10),
          Text(['Plan', 'Fortschritt', 'Profil'][_tab]),
        ]),
        actions: [
          if (_tab == 0 && state.plan != null)
            IconButton(
              tooltip: 'Coach-Chat',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatScreen())),
            ),
        ],
      ),
      body: state.anamnese == null && _tab != 2 ? const _Onboarding() : pages[_tab],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.active != null) const ActiveWorkoutBar(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Plan'),
              NavigationDestination(icon: Icon(Icons.show_chart), label: 'Fortschritt'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Leiste über der Navigation, solange ein Training läuft (wie der Mini-Player bei Strava/Spotify).
class ActiveWorkoutBar extends StatefulWidget {
  const ActiveWorkoutBar({super.key});

  @override
  State<ActiveWorkoutBar> createState() => _ActiveWorkoutBarState();
}

class _ActiveWorkoutBarState extends State<ActiveWorkoutBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = context.watch<AppState>().active;
    if (active == null) return const SizedBox.shrink();
    final color = dayTypeColor(active.day['dayType']?.toString());
    final running = active.run != null && active.run!.phase != 'done';
    return Material(
      color: color,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkoutScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(running ? Icons.directions_run : Icons.fitness_center, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(running ? 'Lauf läuft' : 'Training läuft',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(active.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Text(formatSec(active.elapsedSec),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context) {
    final name = context.read<AppState>().userName ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Willkommen, $name!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text(
              'Mit der Anamnese erfasst die App deine bisherigen Hyrox-Ergebnisse, Ziele, Trainingstage und Equipment. '
              'Daraus entsteht dein Trainingsplan.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.assignment),
              label: const Text('Anamnese starten'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnamneseScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  static String _goalSummary(Map<String, dynamic>? anamnese) {
    final goal = anamnese?['goal'];
    final next = nextRace(anamnese);
    if (goal is Map && goal['mode'] == 'horizon' && goal['horizonDate'] != null) {
      return 'Bestform bis ${germanDate(goal['horizonDate'].toString())}';
    }
    if (next != null) return 'Nächstes Rennen: ${next['name']}, ${germanDate(next['date'].toString())}';
    return 'Offener Aufbau ohne Zeitziel';
  }

  /// Neuen Block von Hand anstoßen. Normalerweise passiert das automatisch 3 Tage vor Blockende.
  Future<void> _adaptDialog(BuildContext context) async {
    final state = context.read<AppState>();
    if (state.planEnvelope == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Es gibt noch keinen Plan.')));
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NewBlockDialog(),
    );
  }

  Future<void> _usage(BuildContext context) async {
    try {
      final u = await context.read<AppState>().loadUsage();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('KI-Nutzung diesen Monat'),
          content: Text(
            'Aufrufe: ${u['callsThisMonth']} von ${u['monthlyLimit']}\n'
            'Tageslimit: ${u['dailyLimit']}\n'
            'Coach-Chat heute: ${u['chatToday'] ?? 0} von ${u['chatDailyLimit'] ?? '–'}\n'
            'Tokens: ${u['inputTokens']} rein, ${u['outputTokens']} raus\n'
            'Modell: ${u['model']}',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person),
          title: Text(state.userName ?? ''),
          subtitle: Text(state.client?.baseUrl ?? ''),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.assignment),
          title: Text(state.anamnese == null ? 'Anamnese starten' : 'Anamnese bearbeiten'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnamneseScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.emoji_events_outlined),
          title: const Text('Rennen & Ziel'),
          subtitle: Text(_goalSummary(state.anamnese)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.auto_fix_high),
          title: const Text('Neuen Block erstellen'),
          subtitle: const Text('Passiert sonst automatisch 3 Tage vor Blockende'),
          onTap: () => _adaptDialog(context),
        ),
        const _HealthTile(),
        const _WatchRunsTile(),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Erinnerungen'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReminderSettingsScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.data_usage),
          title: const Text('KI-Nutzung'),
          onTap: () => _usage(context),
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Daten neu laden'),
          onTap: () async {
            try {
              await context.read<AppState>().refresh();
            } on ApiException catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              }
            }
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Abmelden'),
          onTap: () => context.read<AppState>().logout(),
        ),
      ],
    );
  }
}


/// Apple Health / Watch verbinden und Trainings übernehmen.
class _HealthTile extends StatefulWidget {
  const _HealthTile();

  @override
  State<_HealthTile> createState() => _HealthTileState();
}

class _HealthTileState extends State<_HealthTile> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    HealthSync.instance.enabled.then((v) => mounted ? setState(() => _enabled = v) : null);
  }

  Future<void> _toggle(bool on) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (on) {
        final ok = await HealthSync.instance.connect();
        if (!ok) {
          messenger.showSnackBar(const SnackBar(content: Text('Kein Zugriff auf Apple Health erlaubt.')));
          return;
        }
        final res = await state.syncHealthNow();
        messenger.showSnackBar(SnackBar(
          content: Text(res == null
              ? 'Verbunden.'
              : 'Verbunden: ${res['created']} Trainings übernommen, ${res['merged']} ergänzt.'),
        ));
      } else {
        await HealthSync.instance.disconnect();
      }
      if (mounted) setState(() => _enabled = on);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Apple Health: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.watch_outlined),
      title: const Text('Apple Health / Watch'),
      subtitle: const Text('Watch-Trainings übernehmen und mit dem Plan zusammenführen'),
      value: _enabled ?? false,
      onChanged: _enabled == null || _busy ? null : _toggle,
    );
  }
}


/// Geplante Läufe als Workouts auf die Apple Watch legen (WorkoutKit).
class _WatchRunsTile extends StatefulWidget {
  const _WatchRunsTile();

  @override
  State<_WatchRunsTile> createState() => _WatchRunsTileState();
}

class _WatchRunsTileState extends State<_WatchRunsTile> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WatchWorkouts.instance.enabled.then((v) => mounted ? setState(() => _enabled = v) : null);
  }

  Future<void> _toggle(bool on) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (on && !await WatchWorkouts.instance.supported) {
        messenger.showSnackBar(const SnackBar(content: Text('Auf diesem Gerät nicht möglich – ist eine Apple Watch gekoppelt?')));
        return;
      }
      await WatchWorkouts.instance.setEnabled(on);
      if (on) {
        final n = await WatchWorkouts.instance.sync(state.plan, state.doneKeys);
        messenger.showSnackBar(SnackBar(content: Text('${n ?? 0} Läufe der nächsten 14 Tage auf der Watch geplant.')));
      }
      if (mounted) setState(() => _enabled = on);
    } catch (e) {
      await WatchWorkouts.instance.setEnabled(false).catchError((_) {});
      messenger.showSnackBar(SnackBar(content: Text('Apple Watch: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.directions_run),
      title: const Text('Läufe auf die Apple Watch'),
      subtitle: const Text('Geplante Läufe erscheinen in der Training-App der Watch, mit Pace-Alarm'),
      value: _enabled ?? false,
      onChanged: _enabled == null || _busy ? null : _toggle,
    );
  }
}


class _NewBlockDialog extends StatefulWidget {
  const _NewBlockDialog();

  @override
  State<_NewBlockDialog> createState() => _NewBlockDialogState();
}

class _NewBlockDialogState extends State<_NewBlockDialog> {
  final _notes = TextEditingController();
  bool _startNow = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().adaptPlan(_notes.text, startNow: _startNow);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final end = context.read<AppState>().planEnd;
    return AlertDialog(
      title: const Text('Neuen Block erstellen'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Der Coach plant den nächsten Block anhand deiner Ergebnisse. Länge und Start ergeben sich aus deinem Ziel.'),
          const SizedBox(height: 12),
          RadioGroup<bool>(
            groupValue: _startNow,
            onChanged: _busy ? (_) {} : (v) => setState(() => _startNow = v ?? false),
            child: Column(children: [
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: false,
                title: const Text('Im Anschluss'),
                subtitle: Text(end == null ? '' : 'ab ${germanDate(isoDate(end.add(const Duration(days: 1))))}'),
              ),
              const RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text('Ab dieser Woche'),
                subtitle: Text('Ersetzt den laufenden Plan'),
              ),
            ]),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Anmerkungen (optional)',
              hintText: 'z. B. Sled war zu schwer, Knie zwickt',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: _busy ? null : _create, child: const Text('Erstellen')),
      ],
    );
  }
}
