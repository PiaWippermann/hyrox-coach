import 'package:flutter/material.dart';

import '../util.dart';
import 'workout_screen.dart';

/// Tagesansicht: hier wählt man pro Trainingstag zwischen Gym- und Home-Variante.
/// Beide Varianten stecken schon im Plan, die Auswahl braucht keinen KI-Aufruf.
class DayDetailScreen extends StatefulWidget {
  const DayDetailScreen({super.key, required this.day, required this.planId});

  final Map<String, dynamic> day;
  final String planId;

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  late String _location;

  List<Map<String, dynamic>> get _variants => asMapList(widget.day['variants']);

  @override
  void initState() {
    super.initState();
    _location = _variants.first['location'].toString();
  }

  Map<String, dynamic> get _selected => _variants.firstWhere((v) => v['location'] == _location);

  @override
  Widget build(BuildContext context) {
    final blocks = asMapList(_selected['blocks']);
    final both = _variants.length > 1;

    return Scaffold(
      appBar: AppBar(title: Text(germanDate(widget.day['date'].toString()))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.day['title'].toString(), style: Theme.of(context).textTheme.headlineSmall),
          if (widget.day['intent'] != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(widget.day['intent'].toString()),
          ),
          const SizedBox(height: 16),
          if (both)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gym', label: Text('Gym'), icon: Icon(Icons.fitness_center)),
                ButtonSegment(value: 'home', label: Text('Zuhause'), icon: Icon(Icons.home)),
              ],
              selected: {_location},
              onSelectionChanged: (s) => setState(() => _location = s.first),
            )
          else
            Chip(
              avatar: Icon(_location == 'gym' ? Icons.fitness_center : Icons.home, size: 18),
              label: Text(_location == 'gym' ? 'Nur Gym vorgesehen' : 'Nur Zuhause vorgesehen'),
            ),
          const SizedBox(height: 16),
          for (final block in blocks) ...[
            Text(block['name'].toString(), style: Theme.of(context).textTheme.titleMedium),
            if (block['notes'] != null) Text(block['notes'].toString()),
            for (final ex in asMapList(block['exercises']))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(ex['name'].toString()),
                subtitle: Text(describeExercise(ex)),
              ),
            const Divider(),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text('Training starten (${_location == 'gym' ? 'Gym' : 'Zuhause'})'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkoutScreen(day: widget.day, variant: _selected, planId: widget.planId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
