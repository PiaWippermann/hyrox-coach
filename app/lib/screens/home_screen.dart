import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../util.dart';
import 'anamnese_screen.dart';
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
      appBar: AppBar(title: Text(['Plan', 'Fortschritt', 'Profil'][_tab])),
      body: state.anamnese == null && _tab != 2 ? const _Onboarding() : pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Fortschritt'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profil'),
        ],
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

  Future<void> _adaptDialog(BuildContext context) async {
    final state = context.read<AppState>();
    final env = state.planEnvelope;
    if (env == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Es gibt noch keinen Plan.')));
      return;
    }
    final planStart = parseIso(env['startDate'].toString());
    var start = planStart.add(Duration(days: (env['weeks'] as int) * 7));
    var weeks = 4;
    final notes = TextEditingController();
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Plan anpassen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Die KI erstellt einen Folgeplan anhand dessen, was du bisher geschafft hast. '
                  'Das ist ein KI-Aufruf und zählt zu deinem Monatslimit.',
                ),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2, label: Text('2 Wo.')),
                    ButtonSegment(value: 3, label: Text('3 Wo.')),
                    ButtonSegment(value: 4, label: Text('4 Wo.')),
                  ],
                  selected: {weeks},
                  onSelectionChanged: busy ? null : (s) => setLocal(() => weeks = s.first),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('Start: ${germanDate(isoDate(start))}'),
                  onPressed: busy
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: start,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setLocal(() => start = picked);
                        },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Anmerkungen (optional)',
                    hintText: 'z. B. Sled war zu schwer, Knie zwickt',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
                if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await state.adaptPlan(isoDate(start), weeks, notes.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on ApiException catch (e) {
                        setLocal(() {
                          busy = false;
                          error = e.message;
                        });
                      }
                    },
              child: const Text('Anpassen'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
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
          leading: const Icon(Icons.auto_fix_high),
          title: const Text('Plan anpassen (KI)'),
          subtitle: const Text('Folgeplan anhand deiner absolvierten Einheiten'),
          onTap: () => _adaptDialog(context),
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
