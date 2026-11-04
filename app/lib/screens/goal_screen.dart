import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../widgets/goal_editor.dart';
import 'chat_screen.dart';

/// Rennen und Ziel direkt bearbeiten, ohne die ganze Anamnese zu durchlaufen.
class GoalScreen extends StatefulWidget {
  const GoalScreen({super.key});

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  late final Map<String, dynamic> _anamnese;
  late final Map<String, dynamic> _goal;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Tiefe Kopie über JSON-ähnliches Kopieren der relevanten Teile
    final a = context.read<AppState>().anamnese ?? {};
    _anamnese = Map<String, dynamic>.from(a);
    _goal = Map<String, dynamic>.from((a['goal'] as Map?) ?? {'category': 'single', 'priority': 'improve'});
    _goal['races'] = [for (final r in (_goal['races'] as List?) ?? []) Map<String, dynamic>.from(r as Map)];
    GoalEditor.normalize(_goal);
    _anamnese['goal'] = _goal;
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await state.saveAnamnese(_anamnese);
      if (!mounted) return;
      final adapt = state.plan != null &&
          await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Gespeichert'),
                  content: const Text('Der nächste Plan berücksichtigt dein Ziel automatisch. '
                      'Soll der Coach den aktuellen Plan jetzt schon daran anpassen?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Später')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, anpassen')),
                  ],
                ),
              ) ==
              true;
      if (adapt) {
        navigator.pushReplacement(MaterialPageRoute(
          builder: (_) => const ChatScreen(
            initialMessage: 'Ich habe meine Rennen bzw. mein Ziel geändert. Bitte prüf den aktuellen Plan und passe ihn an '
                '(Periodisierung, Taper, Renntage).',
          ),
        ));
      } else {
        navigator.pop();
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rennen & Ziel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GoalEditor(goal: _goal, onChanged: () => setState(() => _dirty = true)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: !_dirty || _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}
