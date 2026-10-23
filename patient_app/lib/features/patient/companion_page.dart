import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/patient_api.dart';

/// Patient-controlled continuity. Background delivery is a server responsibility.
class CompanionPage extends StatefulWidget {
  const CompanionPage({super.key, required this.api});
  final PatientApi api;
  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends State<CompanionPage> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _messages = [];
  bool _busy = false;
  String? _error;
  Timer? _poll;
  Map<String, dynamic> get _prefs =>
      Map<String, dynamic>.from(_data['preferences'] as Map? ?? {});
  bool get _malayalam => _prefs['language'] == 'ml';

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.companion();
      if (!mounted) return;
      setState(() {
        _data = data;
        _messages = (data['messages'] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .map((e) => Map<String, dynamic>.from(e['data'] as Map))
            .toList();
        _error = null;
      });
      await _check();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _check() async {
    try {
      final value = await widget.api.checkReminders();
      if (mounted) {
        setState(() => _data['notifications'] = value['notifications']);
      }
    } catch (_) {
      /* Keep the last inbox; surface explicit failures on user actions. */
    }
  }

  Future<void> _act(Future<dynamic> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _send() async {
    final message = _composer.text.trim();
    if (message.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.companionChat(message);
      if (!mounted) return;
      setState(() {
        _messages.addAll([
          {'role': 'user', 'text': message},
          {
            'role': 'assistant',
            'text': result['answer'],
            'urgent': result['urgent']
          }
        ]);
        _composer.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _input(String title, String hint) async {
    final input = TextEditingController();
    final answer = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(title),
              content: TextField(
                  controller: input,
                  maxLength: 500,
                  decoration: InputDecoration(hintText: hint)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, input.text.trim()),
                    child: const Text('Save'))
              ],
            ));
    // The closing route can still animate its TextField; dispose after the frame.
    Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    return answer;
  }

  Future<void> _reminder() async {
    final title =
        await _input('A little reminder', 'What would you like to remember?');
    if (title == null || title.isEmpty || !mounted) return;
    final now = DateTime.now();
    final day = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    final repeat = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(title: const Text('Repeat'), children: [
              for (final value in ['none', 'daily', 'weekly'])
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, value),
                    child: Text(value == 'none' ? 'Just once' : value))
            ]));
    if (repeat == null) return;
    final due =
        DateTime(day.year, day.month, day.day, time.hour, time.minute).toUtc();
    await _act(() => widget.api.createReminder({
          'title': title,
          'due_at': due.toIso8601String(),
          'recurrence': repeat
        }));
  }

  void _settings() {
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (c) => StatefulBuilder(
            builder: (c, update) => SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Your memory, your choice',
                                  style: Theme.of(c).textTheme.headlineSmall),
                              const Text(
                                  'Turning memory off stops recall and new chat storage. Delete past messages separately. Your hospital care record is unchanged.'),
                              SwitchListTile(
                                  title:
                                      const Text('Remember our conversations'),
                                  value: _prefs['memory_enabled'] == true,
                                  onChanged: (v) async {
                                    await _act(() => widget.api
                                        .companionPreferences(
                                            {'memory_enabled': v}));
                                    update(() {});
                                  }),
                              SwitchListTile(
                                  title: const Text(
                                      'Use my uploaded health context'),
                                  subtitle: const Text(
                                      'Share a bounded summary with the AI provider to personalise replies.'),
                                  value: _prefs['context_enabled'] == true,
                                  onChanged: (v) async {
                                    await _act(() => widget.api
                                        .companionPreferences(
                                            {'context_enabled': v}));
                                    update(() {});
                                  }),
                              DropdownButtonFormField<String>(
                                  initialValue:
                                      _prefs['language'] as String? ?? 'en',
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'en', child: Text('English')),
                                    DropdownMenuItem(
                                        value: 'ml', child: Text('മലയാളം'))
                                  ],
                                  onChanged: (v) async {
                                    if (v != null) {
                                      await _act(() => widget.api
                                          .companionPreferences(
                                              {'language': v}));
                                      update(() {});
                                    }
                                  }),
                              const SizedBox(height: 12),
                              Text('Things you asked me to remember',
                                  style: Theme.of(c).textTheme.titleMedium),
                              for (final row
                                  in (_data['memories'] as List? ?? [])
                                      .whereType<Map>())
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(row['data']['text'] as String),
                                    trailing: IconButton(
                                        tooltip: 'Forget',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          await _act(() => widget.api
                                              .deleteMemory(
                                                  row['id'] as String));
                                          update(() {});
                                        })),
                              TextButton.icon(
                                  onPressed: _prefs['memory_enabled'] == true
                                      ? () async {
                                          final value = await _input(
                                              'Remember something about me',
                                              'A preference, routine, or something important');
                                          if (value != null &&
                                              value.isNotEmpty) {
                                            await _act(() =>
                                                widget.api.saveMemory(value));
                                            update(() {});
                                          }
                                        }
                                      : null,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add a memory')),
                              TextButton.icon(
                                  onPressed: () async {
                                    final yes = await showDialog<bool>(
                                        context: c,
                                        builder: (d) => AlertDialog(
                                                title: const Text(
                                                    'Delete conversation history?'),
                                                content: const Text(
                                                    'This clears saved companion messages. Your clinical records and saved facts remain.'),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              d, false),
                                                      child:
                                                          const Text('Keep')),
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              d, true),
                                                      child:
                                                          const Text('Delete'))
                                                ]));
                                    if (yes == true) {
                                      await _act(
                                          widget.api.clearCompanionHistory);
                                      update(() {});
                                    }
                                  },
                                  icon: const Icon(Icons.delete_sweep_outlined),
                                  label: const Text(
                                      'Delete conversation history')),
                            ]))))));
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xffFFF9F4),
        appBar: AppBar(
            backgroundColor: const Color(0xffFFF9F4),
            title: const Text('MaatriCare'),
            actions: [
              IconButton(
                  tooltip: 'Memory and language',
                  onPressed: _settings,
                  icon: const Icon(Icons.tune_rounded))
            ],
            bottom: const TabBar(
                tabs: [Tab(text: 'Your companion'), Tab(text: 'Reminders')])),
        body: TabBarView(children: [
          Column(children: [
            Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: const Color(0xffF6E8DF),
                    borderRadius: BorderRadius.circular(24)),
                child: Row(children: [
                  const CircleAvatar(
                      backgroundColor: Color(0xffFFF9F4),
                      child:
                          Icon(Icons.spa_outlined, color: Color(0xffA96552))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            _malayalam
                                ? 'നിങ്ങൾക്ക് പറയാനുള്ളത് കേൾക്കാം'
                                : 'A little space, just for you',
                            style: Theme.of(context).textTheme.titleMedium),
                        const Text(
                            'Your AI companion for everyday support. For urgent help, contact emergency care.',
                            style: TextStyle(fontSize: 12))
                      ]))
                ])),
            Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                                _malayalam
                                    ? 'ഇന്ന് എങ്ങനെയുണ്ട്? മനസ്സിലുള്ളത് പറയാം.'
                                    : 'How are you feeling today?\nYou can share what is on your mind.',
                                textAlign: TextAlign.center)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        itemCount: _messages.length,
                        itemBuilder: (c, i) {
                          final item = _messages[i];
                          final mine = item['role'] == 'user';
                          return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 340),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                      color: item['urgent'] == true
                                          ? const Color(0xffFFE0D8)
                                          : mine
                                              ? const Color(0xffE2EFE6)
                                              : Colors.white,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(item['text'] as String? ?? '')));
                        })),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xffA13734)))),
            SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                              child: TextField(
                                  controller: _composer,
                                  maxLength: 2000,
                                  minLines: 1,
                                  maxLines: 4,
                                  enabled: !_busy,
                                  decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.white,
                                      hintText: _malayalam
                                          ? 'മനസ്സിലുള്ളത് പറയൂ…'
                                          : 'What is on your mind?',
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(24))),
                                  onSubmitted: (_) => _send())),
                          const SizedBox(width: 8),
                          Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: IconButton.filled(
                                  tooltip: 'Send',
                                  onPressed: _busy ? null : _send,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.arrow_upward_rounded)))
                        ]))),
          ]),
          ListView(padding: const EdgeInsets.all(20), children: [
            Text('Small things, gently remembered',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
                'Your reminder inbox is kept by the server worker. Open the app to see it; device push notifications are not configured in this release.'),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: _reminder,
                icon: const Icon(Icons.add),
                label: const Text('Add a reminder')),
            for (final item
                in (_data['reminders'] as List? ?? []).whereType<Map>())
              Card(
                  child: ListTile(
                      title: Text(item['data']['title'] as String),
                      subtitle: Text(
                          '${DateTime.tryParse(item['data']['due_at'] as String)?.toLocal()} · ${item['data']['recurrence']} · ${item['data']['status']}'),
                      trailing: PopupMenuButton<String>(
                          onSelected: (action) => _act(() => widget.api
                              .changeReminder(item['id'] as String, action)),
                          itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'done', child: Text('Done')),
                                PopupMenuItem(
                                    value: 'snooze',
                                    child: Text('Snooze 15 minutes')),
                                PopupMenuItem(
                                    value: 'cancel', child: Text('Cancel'))
                              ]))),
            const SizedBox(height: 20),
            Text('Your inbox', style: Theme.of(context).textTheme.titleLarge),
            for (final item
                in (_data['notifications'] as List? ?? []).whereType<Map>())
              Card(
                  child: ListTile(
                      leading: const Icon(Icons.notifications_none_rounded),
                      title: Text(item['data']['title'] as String),
                      subtitle: Text(
                          DateTime.tryParse(item['data']['due_at'] as String)
                                  ?.toLocal()
                                  .toString() ??
                              ''))),
          ])
        ]),
      ));
}
