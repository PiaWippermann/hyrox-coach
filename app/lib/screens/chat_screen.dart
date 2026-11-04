import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../util.dart';

/// Chat mit dem KI-Coach über den aktuellen Plan. Der Coach kann einzelne Tage direkt ändern.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.initialMessage, this.startCheckin = false});

  /// Startet den Zwei-Wochen-Check-in, sobald der Verlauf geladen ist.
  final bool startCheckin;

  /// Wird nach dem Laden automatisch gesendet (z. B. nach einer Zieländerung oder einem Ausfall).
  final String? initialMessage;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  static const _suggestions = [
    'Tausch Dienstag und Donnerstag',
    'Diese Woche bitte etwas weniger Laufen',
    'Mein Knie zwickt, mach die Beine-Tage schonender',
    'Warum ist Freitag ein Ruhetag?',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final msgs = await context.read<AppState>().loadChat();
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _scrollDown();
      if (widget.initialMessage != null) await _send(widget.initialMessage);
      if (widget.startCheckin) await _checkin();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _checkin() async {
    setState(() {
      _messages = [..._messages, {'role': 'user', 'text': 'Zwei-Wochen-Check-in'}];
      _sending = true;
      _error = null;
    });
    _scrollDown();
    try {
      final reply = await context.read<AppState>().runCheckin();
      if (mounted) setState(() => _messages = [..._messages, reply]);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages.sublist(0, _messages.length - 1);
          _error = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages = [..._messages, {'role': 'user', 'text': text}];
      _sending = true;
      _error = null;
      _input.clear();
    });
    _scrollDown();
    try {
      final reply = await context.read<AppState>().sendChat(text);
      if (!mounted) return;
      setState(() => _messages = [..._messages, reply]);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _input.text = text;
        _error = e.message;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          CircleAvatar(radius: 16, child: Icon(Icons.sports, size: 18)),
          SizedBox(width: 10),
          Text('Dein Coach'),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    children: [
                      const _Bubble(
                        mine: false,
                        text: 'Hi! Ich kenne deinen Plan und deine Anamnese. Sag mir einfach, was du ändern möchtest – '
                            'Tage tauschen, weniger Umfang, andere Übungen – oder frag, warum etwas so geplant ist.',
                      ),
                      for (final m in _messages)
                        _Bubble(
                          mine: m['role'] == 'user',
                          text: m['text'].toString(),
                          changedDates: (m['changedDates'] as List?)?.map((e) => e.toString()).toList() ?? const [],
                        ),
                      if (_sending)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Row(children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Expanded(child: Text('Coach denkt nach … (Planänderungen dauern bis zu einer Minute)')),
                          ]),
                        ),
                      if (_messages.isEmpty && !_sending) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Nachricht an deinen Coach',
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.mine, required this.text, this.changedDates = const []});

  final bool mine;
  final String text;
  final List<String> changedDates;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface)),
            if (changedDates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final d in changedDates)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.edit_calendar, size: 16),
                      label: Text('${germanDate(d)} geändert'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
