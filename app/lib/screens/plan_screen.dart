import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../util.dart';
import 'anamnese_screen.dart';
import 'chat_screen.dart';
import 'day_detail_screen.dart';
import 'race_screen.dart';
import '../widgets/season_timeline.dart';
import '../theme/app_colors.dart';

/// Wochenansicht nach dem Vorbild von Runna/Strava: Wochenwahl, Wochenleiste, Heute-Karte, Tageskarten.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  int? _week; // Index der angezeigten Woche; null = automatisch (Woche mit heute)

  int _autoWeek(List<CalendarWeek> weeks, DateTime now) {
    final monday = mondayOf(now);
    for (var i = 0; i < weeks.length; i++) {
      if (weeks[i].monday == monday) return i;
    }
    return monday.isBefore(weeks.first.monday) ? 0 : weeks.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plan = state.plan;

    if (plan == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Noch kein Plan vorhanden.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AnamneseScreen()),
                ),
                child: const Text('Anamnese öffnen und Plan erstellen'),
              ),
            ],
          ),
        ),
      );
    }

    final planId = state.planEnvelope!['id'].toString();
    final done = state.doneKeys;
    final anamnese = state.anamnese;
    final today = isoDate(DateTime.now());
    final upcoming = state.upcomingEnvelope;
    final weeks = calendarWeeks(plan, state.upcomingPlan);
    // Tage des Folgeblocks gehören zu dessen Plan-Id (für das Protokollieren von Trainings)
    String planIdFor(String date) =>
        upcoming != null && date.compareTo(upcoming['startDate'].toString()) >= 0 ? upcoming['id'].toString() : planId;
    if (weeks.isEmpty) return const Center(child: Text('Der Plan enthält keine Tage.'));
    final weekIndex = (_week ?? _autoWeek(weeks, DateTime.now())).clamp(0, weeks.length - 1);
    final week = weeks[weekIndex];
    final days = week.planDays.toList();
    final todayDay = days.where((d) => d['date'] == today).firstOrNull;

    void openRace(Map<String, dynamic> race) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => RaceScreen(race: race)));

    void openDay(Map<String, dynamic> day) {
      // Renntag: aus dem Plan oder ein Rennen aus der Anamnese an diesem Datum (der Plan kann dort z. B. Ruhetag haben)
      final race = racesOn(anamnese, day['date'].toString()).firstOrNull;
      if (day['dayType'] == 'race' || race != null) {
        openRace(race ??
            {'name': day['title'].toString().replaceFirst('Rennen: ', ''), 'date': day['date'], 'priority': 'A'});
        return;
      }
      if (asMapList(day['variants']).isEmpty) return; // Ruhetag: nichts zu öffnen
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DayDetailScreen(day: day, planId: planIdFor(day['date'].toString())),
      ));
    }

    final upcomingRace = nextRace(anamnese);
    final raceInDays = upcomingRace == null ? null : parseIso(upcomingRace['date'].toString()).difference(parseIso(today)).inDays;

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (upcomingRace != null && raceInDays! <= 21)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppColors.race,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: const Icon(Icons.emoji_events, color: Colors.white),
                  title: Text(
                    raceInDays == 0 ? 'Heute: ${upcomingRace['name']}' : '${upcomingRace['name']} in $raceInDays Tagen',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Prognose, Split-Plan & Checkliste', style: TextStyle(color: Colors.white70)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white),
                  onTap: () => openRace(upcomingRace),
                ),
              ),
            ),
          if (upcoming != null) _NextBlockBanner(envelope: upcoming),
          if (state.checkinDue)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                margin: EdgeInsets.zero,
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('Zeit für deinen Check-in', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Der Coach wertet die letzten 2 Wochen aus und schlägt Anpassungen vor.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatScreen(startCheckin: true)),
                  ),
                ),
              ),
            ),
          _WeekHeader(
            anamnese: anamnese,
            week: week,
            index: weekIndex,
            count: weeks.length,
            done: done,
            onPrev: weekIndex > 0 ? () => setState(() => _week = weekIndex - 1) : null,
            onNext: weekIndex < weeks.length - 1 ? () => setState(() => _week = weekIndex + 1) : null,
          ),
          const SizedBox(height: 12),
          _WeekStrip(week: week, done: done, today: today, anamnese: anamnese, onTap: openDay),
          if (todayDay != null) ...[
            if (!isFixedDuplicate(anamnese, todayDay)) ...[
              const SizedBox(height: 16),
              _TodayCard(
              day: todayDay,
              isDone: done.contains(doneKey(today, todayDay['title'])),
              hasFixed: fixedSessionsOn(anamnese, today).isNotEmpty,
                onTap: () => openDay(todayDay),
              ),
            ],
            for (final f in fixedSessionsOn(anamnese, today))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _FixedTile(date: today, fixed: f, done: done.contains(doneKey(today, f['title']))),
              ),
          ],
          const SizedBox(height: 20),
          Text('Diese Woche', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final day in days) ...[
            // Ruhetag mit festem Termin oder Plantag, der der Kurs selbst ist: nur den Termin zeigen
            if (_showDayCard(anamnese, day))
              _DayCard(
                day: day,
                isDone: done.contains(doneKey(day['date'].toString(), day['title'])),
                isToday: day['date'] == today,
                isPast: day['date'].toString().compareTo(today) < 0,
                onTap: () => openDay(day),
              ),
            // Rennen aus der Anamnese, die der Plan (noch) nicht als Renntag kennt
            if (day['dayType'] != 'race')
              for (final r in racesOn(anamnese, day['date'].toString()))
                Padding(
                  padding: const EdgeInsets.only(left: 52, top: 4, bottom: 4),
                  child: Material(
                    color: AppColors.race.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.emoji_events, color: AppColors.race),
                      title: Text('Rennen: ${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(racePriorityLabels[r['priority']] ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openRace(r),
                    ),
                  ),
                ),
            for (final (i, f) in fixedSessionsOn(anamnese, day['date'].toString()).indexed)
              _FixedTile(
                date: day['date'].toString(),
                fixed: f,
                done: done.contains(doneKey(day['date'].toString(), f['title'])),
                showDate: !_showDayCard(anamnese, day) && i == 0, // Datum, wenn keine Tageskarte darüber steht
                indent: true,
              ),
          ],
          const SizedBox(height: 16),
          SeasonTimeline(
            anamnese: anamnese,
            blocks: [
              (parseIso(state.planEnvelope!['startDate'].toString()), state.planEnd!, false),
              if (upcoming != null)
                (
                  parseIso(upcoming['startDate'].toString()),
                  parseIso(upcoming['startDate'].toString()).add(Duration(days: (upcoming['weeks'] as int) * 7 - 1)),
                  true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _PlanInfo(plan: plan),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Plan mit dem Coach anpassen'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatScreen())),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.sick_outlined),
            label: const Text('Ausfall melden (krank, Urlaub …)'),
            onPressed: () async {
              final message = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const _AbsenceSheet(),
              );
              if (message != null && context.mounted) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(initialMessage: message)));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.anamnese,
    required this.week,
    required this.index,
    required this.count,
    required this.done,
    this.onPrev,
    this.onNext,
  });

  final Map<String, dynamic>? anamnese;
  final CalendarWeek week;
  final int index;
  final int count;
  final Set<String> done;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final sessions = week.planDays.where((d) => d['dayType'] != 'rest' && !isFixedDuplicate(anamnese, d)).toList();
    final finished = sessions.where((d) => done.contains(doneKey(d['date'].toString(), d['title']))).length;
    final minutes = sessions.fold<int>(0, (s, d) => s + ((d['durationMin'] as num?)?.toInt() ?? 0));
    final meters = sessions.fold<double>(0, (s, d) => s + (plannedRunMeters(d) ?? 0));
    final first = week.monday;
    final last = week.monday.add(const Duration(days: 6));
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Column(
                children: [
                  Text('Woche ${index + 1} von $count', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    '${first.day}.${first.month}. – ${last.day}.${last.month}.${week.theme == null ? '' : '  ·  ${week.theme}'}',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Stat(value: '$finished/${sessions.length}', label: 'Einheiten'),
            _Stat(value: '${(minutes / 60).toStringAsFixed(1).replaceAll('.', ',')} h', label: 'geplant'),
            _Stat(value: meters > 0 ? formatKm(meters) : '–', label: 'Laufen'),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: sessions.isEmpty ? 0 : finished / sessions.length,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// Mo–So als farbige Kreise mit Symbol, Haken bei erledigten Tagen, Ring um heute.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.week,
    required this.done,
    required this.today,
    required this.anamnese,
    required this.onTap,
  });

  final CalendarWeek week;
  final Map<String, dynamic>? anamnese;
  final Set<String> done;
  final String today;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (context) {
              final d = week.days[i];
              final date = isoDate(week.monday.add(Duration(days: i)));
              if (d == null) return _OutsideDay(date: date, isToday: date == today);
              final type = d['dayType'].toString();
              if (racesOn(anamnese, date).isNotEmpty || type == 'race') {
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(d),
                  child: _StripDay(
                    date: date,
                    isToday: date == today,
                    color: AppColors.race,
                    icon: Icons.emoji_events,
                    done: false,
                  ),
                );
              }
              // Ruhetag mit festem Termin zeigt das Symbol des Termins
              final fixed = type == 'rest' || isFixedDuplicate(anamnese, d) ? fixedSessionsOn(anamnese, date).firstOrNull : null;
              if (fixed != null) {
                return _StripDay(
                  date: date,
                  isToday: date == today,
                  color: dayTypeColor(fixed['dayType']?.toString()),
                  icon: Icons.event_available,
                  done: done.contains(doneKey(date, fixed['title'])),
                  outlined: true,
                );
              }
              final isRest = type == 'rest';
              final isDone = done.contains(doneKey(date, d['title']));
              final color = dayTypeColor(type);
              final dt = parseIso(date);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: isRest ? null : () => onTap(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Text(weekdayShort[dt.weekday - 1],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: date == today ? FontWeight.w700 : FontWeight.w400,
                            color: date == today ? scheme.primary : null,
                          )),
                      const SizedBox(height: 4),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone ? color : (isRest ? scheme.surfaceContainerHighest : color.withValues(alpha: 0.15)),
                          border: date == today ? Border.all(color: scheme.primary, width: 2) : null,
                        ),
                        child: Icon(
                          isDone ? Icons.check : dayTypeIcon(type),
                          size: 18,
                          color: isDone ? Colors.white : (isRest ? scheme.outline : color),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('${dt.day}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

/// Tageskarte zeigen? Nicht bei Ruhetagen mit festem Termin und nicht bei Plantagen, die der Kurs selbst sind.
bool _showDayCard(Map<String, dynamic>? anamnese, Map<String, dynamic> day) =>
    !(day['dayType'] == 'rest' && fixedSessionsOn(anamnese, day['date'].toString()).isNotEmpty) &&
    !isFixedDuplicate(anamnese, day);

/// Tag in der Wochenleiste mit festem Termin: umrandeter Kreis in der Farbe der Terminart.
class _StripDay extends StatelessWidget {
  const _StripDay({
    required this.date,
    required this.isToday,
    required this.color,
    required this.icon,
    required this.done,
    this.outlined = false,
  });

  final String date;
  final bool isToday;
  final Color color;
  final IconData icon;
  final bool done;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dt = parseIso(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        Text(weekdayShort[dt.weekday - 1],
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              color: isToday ? scheme.primary : null,
            )),
        const SizedBox(height: 4),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? color : null,
            border: Border.all(color: isToday ? scheme.primary : color, width: isToday ? 2 : 1.5),
          ),
          child: Icon(done ? Icons.check : icon, size: 18, color: done ? Colors.white : color),
        ),
        const SizedBox(height: 2),
        Text('${dt.day}', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

/// Fester Termin (Kurs) als abhakbare Zeile. Es wird nichts geplant, nur erledigt markiert.
class _FixedTile extends StatefulWidget {
  const _FixedTile({
    required this.date,
    required this.fixed,
    required this.done,
    this.showDate = false,
    this.indent = false,
  });

  final String date;
  final Map<String, dynamic> fixed;
  final bool done;
  final bool showDate; // Datumsspalte zeigen (Tag ohne eigenes Training)
  final bool indent; // in der Tagesliste unter die Tageskarte einrücken

  @override
  State<_FixedTile> createState() => _FixedTileState();
}

class _FixedTileState extends State<_FixedTile> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().toggleFixed(widget.date, widget.fixed);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixed;
    final color = dayTypeColor(f['dayType']?.toString());
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final dt = parseIso(widget.date);
    final future = widget.date.compareTo(isoDate(DateTime.now())) > 0;

    final tile = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        color: widget.done ? color.withValues(alpha: 0.12) : null,
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(children: [
        Icon(Icons.event_available, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f['time']}  ·  ${f['title']}', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('Fester Termin  ·  ${f['durationMin']} Min', style: text.bodySmall),
          ]),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            tooltip: widget.done ? 'Als nicht erledigt markieren' : 'Abhaken',
            onPressed: future ? null : _toggle,
            icon: Icon(
              widget.done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: widget.done ? AppColors.success : scheme.outline,
            ),
          ),
      ]),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (widget.indent)
          SizedBox(
            width: 52,
            child: widget.showDate
                ? Column(children: [
                    Text(weekdayShort[dt.weekday - 1], style: text.bodySmall),
                    Text('${dt.day}', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ])
                : null,
          ),
        Expanded(child: tile),
      ]),
    );
  }
}

/// Tag der Kalenderwoche, der nicht mehr (oder noch nicht) zum Plan gehört.
class _OutsideDay extends StatelessWidget {
  const _OutsideDay({required this.date, required this.isToday});
  final String date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dt = parseIso(date);
    return Opacity(
      opacity: 0.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          Text(weekdayShort[dt.weekday - 1], style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isToday ? scheme.primary : scheme.outlineVariant),
            ),
            child: Icon(Icons.remove, size: 16, color: scheme.outline),
          ),
          const SizedBox(height: 2),
          Text('${dt.day}', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

String _metaLine(Map<String, dynamic> day) {
  final variants = asMapList(day['variants']);
  final places = variants.map((v) => v['location'] == 'gym' ? 'Gym' : 'Zuhause').join(' / ');
  final meters = plannedRunMeters(day);
  return [
    '${day['durationMin']} Min',
    if (meters != null) formatKm(meters),
    if (places.isNotEmpty) places,
  ].join('  ·  ');
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.day, required this.isDone, required this.hasFixed, required this.onTap});

  final Map<String, dynamic> day;
  final bool isDone;
  final bool hasFixed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = day['dayType'].toString();
    final color = dayTypeColor(type);
    final isRest = type == 'rest';

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isRest ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(dayTypeIcon(type), color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'HEUTE  ·  ${(dayTypeLabels[type] ?? type).toUpperCase()}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isRest ? (hasFixed ? 'Kein Training geplant – nur dein Termin' : 'Ruhetag – erhol dich gut') : day['title'].toString(),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              if (!isRest) ...[
                const SizedBox(height: 4),
                Text(_metaLine(day), style: const TextStyle(color: Colors.white70)),
                if (day['intent'] != null) ...[
                  const SizedBox(height: 8),
                  Text(day['intent'].toString(), style: const TextStyle(color: Colors.white)),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: color),
                  icon: Icon(isDone ? Icons.check_circle : Icons.play_arrow),
                  label: Text(isDone ? 'Erledigt – Details ansehen' : 'Training ansehen und starten'),
                  onPressed: onTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.isDone,
    required this.isToday,
    required this.isPast,
    required this.onTap,
  });

  final Map<String, dynamic> day;
  final bool isDone;
  final bool isToday;
  final bool isPast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = day['dayType'].toString();
    final isRest = type == 'rest';
    final color = dayTypeColor(type);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dt = parseIso(day['date'].toString());
    final missed = isPast && !isDone && !isRest;

    final dateColumn = SizedBox(
      width: 44,
      child: Column(
        children: [
          Text(weekdayShort[dt.weekday - 1], style: text.bodySmall?.copyWith(color: isToday ? scheme.primary : null)),
          Text('${dt.day}',
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isToday ? scheme.primary : null,
              )),
        ],
      ),
    );

    if (isRest) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            dateColumn,
            const SizedBox(width: 8),
            Icon(Icons.bedtime_outlined, size: 18, color: scheme.outline),
            const SizedBox(width: 6),
            Text('Ruhetag', style: text.bodyMedium?.copyWith(color: scheme.outline)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 10), child: dateColumn),
          const SizedBox(width: 8),
          Expanded(
            child: Opacity(
              opacity: missed ? 0.55 : 1,
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: isToday ? BorderSide(color: scheme.primary, width: 1.5) : BorderSide.none,
                ),
                child: InkWell(
                  onTap: onTap,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 5, color: color),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(dayTypeIcon(type), size: 14, color: color),
                                    const SizedBox(width: 4),
                                    Text(
                                      (dayTypeLabels[type] ?? type).toUpperCase(),
                                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                                    ),
                                    if (missed) ...[
                                      const SizedBox(width: 6),
                                      Text('· verpasst', style: text.bodySmall),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(day['title'].toString(),
                                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(_metaLine(day), style: text.bodySmall),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(
                            isDone ? Icons.check_circle : Icons.chevron_right,
                            color: isDone ? AppColors.success : scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanInfo extends StatelessWidget {
  const _PlanInfo({required this.plan});

  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final focus = plan['focus'] is Map ? Map<String, dynamic>.from(plan['focus'] as Map) : <String, dynamic>{};
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.info_outline),
        title: Text(plan['title']?.toString() ?? 'Über deinen Plan'),
        subtitle: focus['primary'] != null ? Text('Fokus: ${focus['primary']}') : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan['summary']?.toString() ?? ''),
          if (focus['rationale'] != null) ...[
            const SizedBox(height: 8),
            Text(focus['rationale'].toString(), style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}


/// Ausfall melden: Grund und Zeitraum wählen, der Coach baut den Plan daraufhin schonend um.
class _AbsenceSheet extends StatefulWidget {
  const _AbsenceSheet();

  @override
  State<_AbsenceSheet> createState() => _AbsenceSheetState();
}

class _AbsenceSheetState extends State<_AbsenceSheet> {
  static const _reasons = ['Krank', 'Verletzt', 'Urlaub', 'Keine Zeit'];
  final _note = TextEditingController();
  String _reason = 'Krank';
  DateTimeRange _range = DateTimeRange(start: DateTime.now(), end: DateTime.now().add(const Duration(days: 2)));

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ausfall melden', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Verpasste Einheiten werden nicht nachgeholt, danach geht es schonend weiter.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            for (final r in _reasons)
              ChoiceChip(label: Text(r), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text('${germanDate(isoDate(_range.start))} – ${germanDate(isoDate(_range.end))}'),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: _range,
                firstDate: DateTime.now().subtract(const Duration(days: 14)),
                lastDate: DateTime.now().add(const Duration(days: 60)),
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notiz (optional)', hintText: 'z. B. Erkältung, Knie zwickt, Hotel mit Gym'),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                '[Ausfall] Grund: $_reason. Zeitraum: ${isoDate(_range.start)} bis ${isoDate(_range.end)}.'
                '${_note.text.trim().isEmpty ? '' : ' Notiz: ${_note.text.trim()}'}',
              ),
              child: const Text('An den Coach senden'),
            ),
          ),
        ]),
      ),
    );
  }
}


/// Hinweis auf den automatisch erstellten Folgeblock, bis man ihn einmal angesehen hat.
class _NextBlockBanner extends StatefulWidget {
  const _NextBlockBanner({required this.envelope});
  final Map<String, dynamic> envelope;

  @override
  State<_NextBlockBanner> createState() => _NextBlockBannerState();
}

class _NextBlockBannerState extends State<_NextBlockBanner> {
  static const _key = 'seenUpcomingBlock';
  bool _seen = true;

  String get _id => '${widget.envelope['id']}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _seen = p.getString(_key) == _id);
    });
  }

  Future<void> _show() async {
    final plan = Map<String, dynamic>.from(widget.envelope['plan'] as Map);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plan['title']?.toString() ?? 'Nächster Block', style: Theme.of(ctx).textTheme.titleLarge),
            Text('ab ${germanDate(widget.envelope['startDate'].toString())} · ${widget.envelope['weeks']} Wochen',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(plan['summary']?.toString() ?? ''),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Verstanden')),
            ),
          ]),
        ),
      ),
    );
    (await SharedPreferences.getInstance()).setString(_key, _id);
    if (mounted) setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_seen) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Dein nächster Block ist fertig', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Ab ${germanDate(widget.envelope['startDate'].toString())} – was sich ändert und warum'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _show,
        ),
      ),
    );
  }
}
