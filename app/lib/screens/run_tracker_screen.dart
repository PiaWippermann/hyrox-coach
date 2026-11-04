import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/active_workout.dart';
import '../state/app_state.dart';
import '../util.dart';
import '../theme/app_colors.dart';

/// Geführter Lauf ohne GPS: Stoppuhr, Intervalle mit Zielzeit aus der Zielpace, Trabpausen als Countdown.
/// Der Zustand liegt in ActiveWorkout.run und beruht auf Zeitstempeln: Verlässt man den Screen oder die App,
/// läuft der Lauf weiter. Beim Zurückkommen werden abgelaufene Pausen und Zeit-Intervalle nachgeholt.
class RunTrackerScreen extends StatefulWidget {
  const RunTrackerScreen({super.key, required this.exerciseIndex});

  final int exerciseIndex;

  @override
  State<RunTrackerScreen> createState() => _RunTrackerScreenState();
}

class _RunTrackerScreenState extends State<RunTrackerScreen> {
  late final AppState _state;
  Timer? _timer;

  ActiveWorkout get _w => _state.active!;
  RunState get _run => _w.run!;
  ActiveExercise get _ex => _w.exercises[widget.exerciseIndex];
  int get _laps => _ex.sets.length;
  double? get _lapDistanceM => (_ex.data['distanceM'] as num?)?.toDouble();
  int? get _lapDurationSec => (_ex.data['durationSec'] as num?)?.round();
  int get _restSec => (_ex.data['restSec'] as num?)?.round() ?? 0;
  String? get _targetPace => _ex.data['targetPace']?.toString();
  bool get _timeBased => _lapDistanceM == null && _lapDurationSec != null;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _w.run ??= RunState(exercise: widget.exerciseIndex);
    _catchUp();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _state.active?.run == null) return;
      _catchUp();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _save() => _state.saveActive();

  /// Zielzeit pro Intervall aus Pace × Distanz, z. B. 1000 m bei 5:00/km = 5:00.
  int? get _targetLapSec {
    final pace = _targetPace == null ? null : parseTimeSec(_targetPace!.split('/').first.split('-').first);
    if (pace != null && _lapDistanceM != null) return (pace * _lapDistanceM! / 1000).round();
    return _lapDurationSec;
  }

  /// Holt Übergänge nach, die passiert sind, während niemand hingeschaut hat (Pause vorbei, Zeit-Intervall voll).
  void _catchUp() {
    var changed = false;
    while (true) {
      final now = DateTime.now();
      if (_run.phase == 'resting' && _run.restUntil != null && !now.isBefore(_run.restUntil!)) {
        _beginLap(_run.restUntil!);
      } else if (_run.phase == 'running' && _timeBased && _run.lapMs >= _lapDurationSec! * 1000) {
        final end = _run.segmentStart!.add(Duration(milliseconds: _lapDurationSec! * 1000 - _run.accumulatedMs));
        _run.laps.add(_lapDurationSec!);
        _afterLap(end);
      } else {
        break;
      }
      changed = true;
    }
    if (changed) {
      HapticFeedback.heavyImpact();
      _save();
    }
  }

  void _beginLap(DateTime at) {
    _run
      ..phase = 'running'
      ..segmentStart = at
      ..accumulatedMs = 0
      ..restUntil = null;
  }

  void _afterLap(DateTime at) {
    _run
      ..accumulatedMs = 0
      ..segmentStart = null;
    if (_run.laps.length >= _laps) {
      _run.phase = 'done';
    } else if (_restSec > 0) {
      _run
        ..phase = 'resting'
        ..restUntil = at.add(Duration(seconds: _restSec));
    } else {
      _beginLap(at);
    }
  }

  void _start() {
    setState(() => _beginLap(DateTime.now()));
    _save();
  }

  void _lap() {
    HapticFeedback.mediumImpact();
    setState(() {
      _run.laps.add((_run.lapMs / 1000).round());
      _afterLap(DateTime.now());
    });
    _save();
  }

  void _togglePause() {
    setState(() {
      if (_run.phase == 'running') {
        _run
          ..accumulatedMs = _run.lapMs
          ..segmentStart = null
          ..phase = 'paused';
      } else if (_run.phase == 'paused') {
        _run
          ..segmentStart = DateTime.now()
          ..phase = 'running';
      }
    });
    _save();
  }

  /// Gemessene Zeiten in die Sätze übernehmen und den Lauf abschließen.
  void _apply() {
    if ((_run.phase == 'running' || _run.phase == 'paused') && _run.lapMs >= 1000) {
      _run.laps.add((_run.lapMs / 1000).round());
    }
    for (var i = 0; i < _run.laps.length && i < _ex.sets.length; i++) {
      final s = _ex.sets[i];
      s.time = formatSec(_run.laps[i]);
      if (_lapDistanceM != null) s.distance = fmtNum(_lapDistanceM! / 1000);
      s.done = true;
    }
    _w.run = null;
    _save();
    Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lauf verwerfen?'),
        content: const Text('Die gemessenen Zeiten dieses Laufs gehen verloren. Das Training läuft weiter.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Weiterlaufen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verwerfen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _w.run = null;
    _save();
    Navigator.of(context).pop();
  }

  /// Zurück: Lauf läuft weiter. Nur ein noch nicht gestarteter Lauf wird verworfen.
  void _back() {
    if (_run.phase == 'ready') {
      _w.run = null;
      _save();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_state.active?.run == null) return const Scaffold();
    const color = AppColors.run;
    final phase = _run.phase;
    final lapSec = _run.lapMs ~/ 1000;
    final target = _targetLapSec;
    final resting = phase == 'resting';
    final restLeft = resting ? _run.restUntil!.difference(DateTime.now()).inSeconds.clamp(0, 9999) + 1 : 0;
    final current = _run.laps.length + (phase == 'done' ? 0 : 1);
    final bigTime = switch (phase) {
      'resting' => formatSec(restLeft),
      'ready' => formatSec(0),
      'done' => formatSec(_run.laps.fold(0, (s, l) => s + l)),
      _ => _timeBased ? formatSec((_lapDurationSec! - lapSec).clamp(0, 99999)) : formatSec(lapSec),
    };
    final ahead = target != null && _lapDistanceM != null && phase == 'running' ? target - lapSec : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: resting ? AppColors.espresso : color,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(_ex.name),
          leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), tooltip: 'Minimieren', onPressed: _back),
          actions: [
            if (phase != 'ready')
              PopupMenuButton<String>(
                onSelected: (v) => v == 'discard' ? _discard() : _apply(),
                itemBuilder: (_) => [
                  if (phase != 'done') const PopupMenuItem(value: 'finish', child: Text('Lauf jetzt beenden')),
                  const PopupMenuItem(value: 'discard', child: Text('Lauf verwerfen')),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  switch (phase) {
                    'ready' => _laps > 1 ? '$_laps Intervalle' : 'Bereit',
                    'resting' => 'TRABPAUSE  ·  gleich Intervall ${_run.laps.length + 1}',
                    'done' => 'Geschafft!',
                    'paused' => 'PAUSIERT',
                    _ => _laps > 1 ? 'INTERVALL $current VON $_laps' : 'LÄUFT',
                  },
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
                const Spacer(),
                FittedBox(
                  child: Text(
                    bigTime,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 96,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_lapDistanceM != null) _Info('Distanz', formatKm(_lapDistanceM!)),
                    if (_targetPace != null) _Info('Zielpace', _targetPace!),
                    if (target != null && _lapDistanceM != null) _Info('Zielzeit', formatSec(target)),
                  ],
                ),
                if (ahead != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    ahead >= 0 ? 'noch ${formatSec(ahead)} bis Zielzeit' : '${formatSec(-ahead)} über Zielzeit',
                    style: TextStyle(color: ahead >= 0 ? Colors.white : AppColors.warning, fontSize: 16),
                  ),
                ],
                const Spacer(),
                if (_run.laps.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (var i = 0; i < _run.laps.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Text('${i + 1}', style: const TextStyle(color: Colors.white70)),
                              const SizedBox(width: 16),
                              Text(formatSec(_run.laps[i]),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              Text(formatPace(_run.laps[i], _lapDistanceM) ?? '',
                                  style: const TextStyle(color: Colors.white70)),
                            ]),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                _controls(phase),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(String phase) {
    final big = FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.run,
      minimumSize: const Size.fromHeight(60),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
    switch (phase) {
      case 'ready':
        return FilledButton.icon(style: big, onPressed: _start, icon: const Icon(Icons.play_arrow), label: const Text('Start'));
      case 'resting':
        return FilledButton.icon(
            style: big, onPressed: _start, icon: const Icon(Icons.skip_next), label: const Text('Pause überspringen'));
      case 'done':
        return FilledButton.icon(style: big, onPressed: _apply, icon: const Icon(Icons.check), label: const Text('Übernehmen'));
      default:
        return Row(
          children: [
            IconButton.filledTonal(
              iconSize: 32,
              onPressed: _togglePause,
              icon: Icon(phase == 'paused' ? Icons.play_arrow : Icons.pause),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: big,
                onPressed: _lap,
                icon: const Icon(Icons.flag),
                label: Text(_laps > 1 ? 'Intervall fertig' : 'Lauf beenden'),
              ),
            ),
          ],
        );
    }
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      );
}
