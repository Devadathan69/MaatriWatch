import 'package:flutter/material.dart';
import '../../core/patient_api.dart';
import '../../core/concern_recorder.dart';

class ConcernsPage extends StatefulWidget {
  const ConcernsPage({super.key, required this.api});
  final PatientApi api;
  @override
  State<ConcernsPage> createState() => _ConcernsPageState();
}

class _ConcernsPageState extends State<ConcernsPage> {
  final _text = TextEditingController();
  final _month = TextEditingController(
    text: DateTime.now().toString().substring(0, 7),
  );
  String _language = 'en', _mode = 'manual';
  bool _consent = false,
      _summaryConsent = false,
      _share = false,
      _busy = false,
      _recording = false;
  String? _error, _guidance;
  Map<String, dynamic>? _draft, _summary;
  List<Map<String, dynamic>> _history = [];
  ConcernRecorder? _recorder;
  int _editorVersion = 0;

  Map<String, dynamic> _emptySymptom() => {
    'symptom_key': 'other',
    'name': '',
    'onset': '',
    'frequency': '',
    'severity': 'unknown',
    'details': '',
    'source_quote': '',
  };
  void _manualDraft() {
    _draft = {
      'original_text': '',
      'language': _language,
      'symptoms': [_emptySymptom()],
    };
    _editorVersion++;
  }

  @override
  void initState() {
    super.initState();
    _manualDraft();
    _refresh();
  }

  @override
  void dispose() {
    _text.dispose();
    _month.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final rows = await widget.api.concerns();
      if (mounted) {
        setState(
          () => _history = (rows['items'] as List? ?? [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _voice() async {
    if (!_consent) {
      setState(
        () => _error = 'Allow AI transcription first, or choose manual entry.',
      );
      return;
    }
    if (!_recording) {
      final recorder = ConcernRecorder();
      _recorder = recorder;
      try {
        await recorder.start(() {
          if (mounted && _recording && !_busy) _voice();
        });
        if (!mounted) {
          await recorder.dispose();
          return;
        }
        setState(() {
          _recording = true;
          _error = null;
        });
      } catch (e) {
        await recorder.dispose();
        _recorder = null;
        if (mounted) setState(() => _error = e.toString());
      }
    } else {
      setState(() => _recording = false);
      await _run(() async {
        final recorder = _recorder!;
        try {
          final bytes = await recorder.stop();
          final result = await widget.api.transcribeConcern(
            bytes,
            'concern.wav',
            _language,
          );
          if (mounted) {
            setState(() {
              _text.text = result['transcript'] as String;
              _guidance = result['guidance'] as String?;
              _draft = null;
            });
          }
        } finally {
          await recorder.dispose();
          _recorder = null;
        }
      });
    }
  }

  Future<void> _extract() => _run(() async {
    if (_text.text.trim().isEmpty) {
      throw StateError('Record your concern or enter its transcript first.');
    }
    final result = await widget.api.draftConcern(_text.text.trim(), _language);
    if (mounted) {
      setState(() {
        _draft = Map<String, dynamic>.from(result['draft'] as Map);
        _guidance = result['guidance'] as String?;
        _editorVersion++;
      });
    }
  });
  Future<void> _save() => _run(() async {
    if (_draft == null) return;
    final result = await widget.api.saveConcern({
      ..._draft!,
      'original_text': _mode == 'manual' ? '' : _text.text.trim(),
      'language': _language,
      'entry_mode': _mode,
      'confirmed': true,
      'share_with_care_team': _share,
    });
    if (mounted) {
      setState(() {
        _text.clear();
        _guidance = result['guidance'] as String? ?? 'Saved to your concern history.';
        _summary = null;
        if (_mode == 'manual') {
          _manualDraft();
        } else {
          _draft = null;
        }
      });
    }
    await _refresh();
  });
  Future<void> _summarize({bool ai = false}) => _run(() async {
    final result = await widget.api.concernSummary(
      _month.text.trim(),
      generate: ai,
    );
    if (mounted) {
      setState(
        () => _summary = Map<String, dynamic>.from(result['summary'] as Map),
      );
    }
  });

  Widget _editSymptom(Map item, int index) => Card(
    key: ValueKey('symptom-$_editorVersion-$index'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Symptom ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if ((_draft!['symptoms'] as List).length > 1)
                IconButton(
                  tooltip: 'Remove symptom',
                  onPressed: () => setState(() {
                    (_draft!['symptoms'] as List).removeAt(index);
                    _editorVersion++;
                  }),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          TextFormField(
            initialValue: item['name'] as String? ?? '',
            decoration: const InputDecoration(labelText: 'Symptom'),
            onChanged: (v) => item['name'] = v,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: item['symptom_key'] as String,
            decoration: const InputDecoration(labelText: 'Symptom category'),
            items: [
              for (final key in [
                'headache',
                'abdominal_pain',
                'back_pain',
                'sleep',
                'nausea',
                'fatigue',
                'swelling',
                'other',
              ])
                DropdownMenuItem(
                  value: key,
                  child: Text(key.replaceAll('_', ' ')),
                ),
            ],
            onChanged: (v) => item['symptom_key'] = v,
          ),
          for (final pair in [
            ('onset', 'When did it start?'),
            ('frequency', 'How often?'),
            ('details', 'Anything else?'),
          ]) ...[
            const SizedBox(height: 14),
            TextFormField(
              initialValue: item[pair.$1] as String? ?? '',
              decoration: InputDecoration(labelText: pair.$2),
              onChanged: (v) => item[pair.$1] = v,
            ),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: item['severity'] as String,
            decoration: const InputDecoration(labelText: 'How severe?'),
            items: [
              for (final key in ['unknown', 'mild', 'moderate', 'severe'])
                DropdownMenuItem(
                  value: key,
                  child: Text(key == 'unknown' ? 'Not sure' : _label(key)),
                ),
            ],
            onChanged: (v) => item['severity'] = v,
          ),
          if ((item['source_quote'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'From your recording: “${item['source_quote']}”',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
  );

  String _label(String value) => value.isEmpty
      ? ''
      : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';
  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '' : '${date.day}/${date.month}/${date.year}';
  }

  void _sources(List ids) {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Supporting reports', style: Theme.of(c).textTheme.titleLarge),
            for (final row in _history.where((r) => ids.contains(r['id'])))
              ListTile(
                title: Text(
                  (row['data']['symptoms'] as List)
                      .map((s) => s['name'])
                      .join(', '),
                ),
                subtitle: Text(
                  '${_date(row['created_at'])}\n${row['data']['original_text']}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _monthly() {
    final summary = _summary;
    final insights = (summary?['ai_insights'] as List? ?? [])
        .whereType<Map>()
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Your month at a glance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'A brief record of what you experienced, how severe it felt, and patterns to discuss at your next visit.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _month,
          decoration: const InputDecoration(labelText: 'Month (YYYY-MM)'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Allow AI to summarise this month’s saved concerns',
          ),
          value: _summaryConsent,
          onChanged: (v) => setState(() => _summaryConsent = v ?? false),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _summarize(),
              child: const Text('View records'),
            ),
            FilledButton(
              onPressed: _busy || !_summaryConsent
                  ? null
                  : () => _summarize(ai: true),
              child: const Text('Generate brief AI report'),
            ),
          ],
        ),
        if (summary != null) ...[
          const SizedBox(height: 18),
          Text(
            '${summary['report_count']} reports · ${summary['urgent_report_count']} urgent flags',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Symptoms & severity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final item
              in (summary['patterns'] as List? ?? []).whereType<Map>())
            Card(
              child: ExpansionTile(
                title: Text(
                  '${item['name']} · ${item['count']} ${item['count'] == 1 ? 'report' : 'reports'}',
                ),
                subtitle: Text(
                  'Highest: ${_label(item['highest_severity'] as String? ?? 'unknown')} · ${switch (item['reported_severity_change']) {
                    'increased' => 'Severity increased',
                    'decreased' => 'Severity decreased',
                    'unchanged' => 'Severity unchanged',
                    _ => 'More reports needed to compare',
                  }}',
                ),
                children: [
                  for (final occurrence
                      in (item['occurrences'] as List).whereType<Map>())
                    ListTile(
                      title: Text(
                        '${_date(occurrence['reported_at'])} · ${_label(occurrence['severity'] as String)}',
                      ),
                      subtitle: Text(
                        '${occurrence['onset']} · ${occurrence['frequency']}',
                      ),
                    ),
                ],
              ),
            ),
          for (final section in [
            ('experienced', 'What you experienced'),
            ('severity', 'Severity & changes'),
            ('patterns', 'Patterns noticed'),
            ('insights', 'Major insights'),
          ])
            if (insights.any((i) => (i['section'] ?? 'insights') == section.$1))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final insight in insights.where(
                        (i) => (i['section'] ?? 'insights') == section.$1,
                      )) ...[
                        Text('• ${insight['text']}'),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                _sources(insight['source_report_ids'] as List),
                            child: const Text('View supporting reports'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          if (insights.isEmpty && summary['report_count'] != 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Generate the AI report for a brief overview and major insights.',
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Based on your reported experiences; this is not a diagnosis.',
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      backgroundColor: const Color(0xffFFF9F4),
      appBar: AppBar(
        title: const Text('Speak Your Concern'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Share'),
            Tab(text: 'History'),
            Tab(text: 'Monthly'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xffA13734)),
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Every concern deserves to be heard.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Record your concern or add symptoms one at a time. For urgent symptoms, get medical help immediately.',
                    ),
                    const SizedBox(height: 18),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'manual',
                          icon: Icon(Icons.edit_note),
                          label: Text('Enter manually'),
                        ),
                        ButtonSegment(
                          value: 'audio',
                          icon: Icon(Icons.mic_none),
                          label: Text('Use audio'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _busy || _recording
                          ? null
                          : (v) => setState(() {
                              _mode = v.first;
                              _draft = null;
                              _guidance = null;
                              _error = null;
                              if (_mode == 'manual') _manualDraft();
                            }),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'en', label: Text('English')),
                        ButtonSegment(value: 'ml', label: Text('മലയാളം')),
                      ],
                      selected: {_language},
                      onSelectionChanged: _busy || _recording
                          ? null
                          : (v) => setState(() => _language = v.first),
                    ),
                    if (_mode == 'audio') ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Allow AI transcription and symptom organisation',
                        ),
                        subtitle: const Text(
                          'Audio is sent for transcription and is not kept by this app.',
                        ),
                        value: _consent,
                        onChanged: _recording || _busy
                            ? null
                            : (v) => setState(() => _consent = v ?? false),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _voice,
                        icon: Icon(
                          _recording ? Icons.stop_circle : Icons.mic_none,
                        ),
                        label: Text(
                          _recording
                              ? 'Stop & transcribe'
                              : 'Record your concern',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _text,
                        maxLength: 4000,
                        minLines: 3,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          labelText: 'Your recording as text',
                          hintText:
                              'Your transcript appears here. You can correct it before continuing.',
                        ),
                        onChanged: (_) {
                          if (_draft != null) {
                            setState(() => _draft = null);
                          }
                        },
                      ),
                      FilledButton(
                        onPressed: _busy || !_consent || _recording
                            ? null
                            : _extract,
                        child: const Text('Organise symptoms with AI'),
                      ),
                    ],
                    if (_guidance != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_guidance!),
                      ),
                    if (_draft != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        _mode == 'manual'
                            ? 'Add your symptoms'
                            : 'Review your symptoms',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (
                        var i = 0;
                        i < (_draft!['symptoms'] as List).length;
                        i++
                      )
                        _editSymptom(
                          (_draft!['symptoms'] as List)[i] as Map,
                          i,
                        ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => (_draft!['symptoms'] as List).add(
                                  _emptySymptom(),
                                ),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add symptom'),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Include these symptoms in my care team’s monthly view',
                        ),
                        value: _share,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _share = v ?? false),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.check),
                        label: const Text('Save to my history'),
                      ),
                    ],
                  ],
                ),
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_history.isEmpty)
                        const Text(
                          'Your saved concerns will appear here over time.',
                        ),
                      for (final row in _history)
                        Card(
                          child: ExpansionTile(
                            title: Text(
                              (row['data']['symptoms'] as List)
                                  .map((s) => s['name'])
                                  .join(', '),
                            ),
                            subtitle: Text(
                              '${_date(row['created_at'])} · ${row['data']['share_with_care_team'] == true ? 'Shared monthly view' : 'Private'}',
                            ),
                            children: [
                              for (final s
                                  in (row['data']['symptoms'] as List)
                                      .whereType<Map>())
                                ListTile(
                                  title: Text(
                                    '${s['name']} · ${_label(s['severity'] as String)}',
                                  ),
                                  subtitle: Text(
                                    '${s['onset']} · ${s['frequency']}\n${s['details']}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                _monthly(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
