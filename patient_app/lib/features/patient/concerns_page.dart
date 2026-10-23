import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  final _month =
      TextEditingController(text: DateTime.now().toString().substring(0, 7));
  String _language = 'en';
  bool _consent = false, _share = true, _busy = false, _recording = false;
  String? _error, _guidance;
  Map<String, dynamic>? _draft, _summary;
  List<Map<String, dynamic>> _history = [];
  ConcernRecorder? _recorder;
  @override
  void initState() {
    super.initState();
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
        setState(() => _history = (rows['items'] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _voice() async {
    if (!_consent) {
      setState(() => _error =
          'Please allow AI processing before recording. Typing and manual entry are also available.');
      return;
    }
    if (!_recording) {
      try {
        final recorder = ConcernRecorder();
        _recorder = recorder;
        await recorder.start(() {
          if (_recording && !_busy) _voice();
        });
        if (mounted) setState(() => _recording = true);
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    } else {
      setState(() => _recording = false);
      await _run(() async {
        final recorder = _recorder!;
        final bytes = await recorder.stop();
        await recorder.dispose();
        _recorder = null;
        final result =
            await widget.api.transcribeConcern(bytes, 'concern.wav', _language);
        if (mounted) {
          setState(() {
            _text.text = result['transcript'] as String;
            _guidance = result['guidance'] as String?;
            _draft = null;
          });
        }
      });
    }
  }

  Future<void> _uploadAudio() => _run(() async {
        if (!_consent) throw StateError('Please allow AI processing first.');
        final file = await FilePicker.pickFile(
            type: FileType.custom,
            allowedExtensions: ['wav', 'm4a', 'mp3', 'webm']);
        if (file == null) return;
        if (await file.length() > 3000000) {
          throw StateError('Choose a recording under 3 MB.');
        }
        final result = await widget.api
            .transcribeConcern(await file.readAsBytes(), file.name, _language);
        if (mounted) {
          setState(() {
            _text.text = result['transcript'] as String;
            _guidance = result['guidance'] as String?;
            _draft = null;
          });
        }
      });
  Future<void> _extract() => _run(() async {
        final result =
            await widget.api.draftConcern(_text.text.trim(), _language);
        if (mounted) {
          setState(() {
            _draft = Map<String, dynamic>.from(result['draft'] as Map);
            _guidance = result['guidance'] as String?;
          });
        }
      });
  void _manual() {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Write your concern first.');
      return;
    }
    setState(() => _draft = {
          'original_text': _text.text.trim(),
          'language': _language,
          'symptoms': [
            {
              'symptom_key': 'other',
              'name': '',
              'onset': '',
              'frequency': '',
              'severity': 'unknown',
              'details': '',
              'source_quote': ''
            }
          ]
        });
  }

  Future<void> _save() => _run(() async {
        if (_draft == null) return;
        final result = await widget.api.saveConcern(
            {..._draft!, 'confirmed': true, 'share_with_care_team': _share});
        if (mounted) {
          setState(() {
            _draft = null;
            _text.clear();
            _guidance = result['guidance'] as String?;
          });
        }
        await _refresh();
      });
  Future<void> _summarize({bool ai = false}) => _run(() async {
        final result =
            await widget.api.concernSummary(_month.text.trim(), generate: ai);
        if (mounted) {
          setState(() =>
              _summary = Map<String, dynamic>.from(result['summary'] as Map));
        }
      });

  Widget _editSymptom(Map item, int index) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('Symptom ${index + 1}',
                      style: Theme.of(context).textTheme.titleMedium)),
              if ((_draft!['symptoms'] as List).length > 1)
                IconButton(
                    tooltip: 'Remove symptom',
                    onPressed: () => setState(
                        () => (_draft!['symptoms'] as List).removeAt(index)),
                    icon: const Icon(Icons.close))
            ]),
            TextFormField(
                initialValue: item['name'] as String? ?? '',
                decoration:
                    const InputDecoration(labelText: 'Symptom in your words'),
                onChanged: (v) => item['name'] = v),
            DropdownButtonFormField<String>(
                initialValue: item['symptom_key'] as String,
                decoration:
                    const InputDecoration(labelText: 'Group recurring reports'),
                items: [
                  for (final key in [
                    'headache',
                    'abdominal_pain',
                    'back_pain',
                    'sleep',
                    'nausea',
                    'fatigue',
                    'swelling',
                    'other'
                  ])
                    DropdownMenuItem(
                        value: key, child: Text(key.replaceAll('_', ' ')))
                ],
                onChanged: (v) => item['symptom_key'] = v),
            for (final pair in [
              ('onset', 'When did it start?'),
              ('frequency', 'How often?'),
              ('details', 'Anything else?')
            ])
              TextFormField(
                  initialValue: item[pair.$1] as String? ?? '',
                  decoration: InputDecoration(labelText: pair.$2),
                  onChanged: (v) => item[pair.$1] = v),
            DropdownButtonFormField<String>(
                initialValue: item['severity'] as String,
                decoration:
                    const InputDecoration(labelText: 'Your reported severity'),
                items: [
                  for (final key in ['unknown', 'mild', 'moderate', 'severe'])
                    DropdownMenuItem(value: key, child: Text(key))
                ],
                onChanged: (v) => item['severity'] = v),
            if ((item['source_quote'] as String? ?? '').isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('From your words: “${item['source_quote']}”',
                      style: Theme.of(context).textTheme.bodySmall)),
          ])));

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xffFFF9F4),
        appBar: AppBar(
            title: const Text('Speak Your Concern'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Share'),
              Tab(text: 'History'),
              Tab(text: 'Monthly')
            ])),
        body: Column(children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xffA13734)))),
          Expanded(
              child: TabBarView(children: [
            ListView(padding: const EdgeInsets.all(20), children: [
              Text('Every concern deserves to be heard.',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Speak or write in English or Malayalam. Check the details before saving. For urgent symptoms, get medical help immediately.'),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(value: 'ml', label: Text('മലയാളം'))
                  ],
                  selected: {
                    _language
                  },
                  onSelectionChanged: _recording
                      ? null
                      : (v) => setState(() => _language = v.first)),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow AI processing of this text/audio'),
                  subtitle: const Text(
                      'Audio is sent for transcription, not retained by this app. Provider terms apply.'),
                  value: _consent,
                  onChanged: _recording
                      ? null
                      : (v) => setState(() => _consent = v ?? false)),
              Wrap(spacing: 12, children: [
                FilledButton.icon(
                    onPressed: _busy ? null : _voice,
                    icon: Icon(_recording ? Icons.stop_circle : Icons.mic_none),
                    label: Text(
                        _recording ? 'Stop recording' : 'Speak your concern')),
                TextButton.icon(
                    onPressed: _busy || _recording ? null : _uploadAudio,
                    icon: const Icon(Icons.audio_file_outlined),
                    label: const Text('Upload audio'))
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: _text,
                  maxLength: 4000,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                      hintText: _language == 'ml'
                          ? 'നിങ്ങൾക്ക് എന്താണ് ബുദ്ധിമുട്ട്?'
                          : 'What has been bothering you? When did it start?',
                      border: const OutlineInputBorder()),
                  onChanged: (_) {
                    if (_draft != null) setState(() => _draft = null);
                  }),
              Wrap(spacing: 12, children: [
                FilledButton(
                    onPressed:
                        _busy || !_consent || _recording ? null : _extract,
                    child: const Text('Organise with AI')),
                TextButton(
                    onPressed: _busy || _recording ? null : _manual,
                    child: const Text('Enter details myself'))
              ]),
              if (_guidance != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_guidance!)),
              if (_draft != null) ...[
                Text('Review your report',
                    style: Theme.of(context).textTheme.titleLarge),
                for (var i = 0; i < (_draft!['symptoms'] as List).length; i++)
                  _editSymptom((_draft!['symptoms'] as List)[i] as Map, i),
                TextButton.icon(
                    onPressed: () =>
                        setState(() => (_draft!['symptoms'] as List).add({
                              'symptom_key': 'other',
                              'name': '',
                              'onset': '',
                              'frequency': '',
                              'severity': 'unknown',
                              'details': '',
                              'source_quote': ''
                            })),
                    icon: const Icon(Icons.add),
                    label: const Text('Add symptom')),
                CheckboxListTile(
                    title: const Text('Share this report with my care team'),
                    value: _share,
                    onChanged: (v) => setState(() => _share = v ?? false)),
                FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm and save report')),
              ],
            ]),
            RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  if (_history.isEmpty)
                    const Text(
                        'Your saved concerns will appear here over time.'),
                  for (final row in _history)
                    Card(
                        child: ExpansionTile(
                            title: Text((row['data']['symptoms'] as List)
                                .map((e) => e['name'])
                                .join(', ')),
                            subtitle: Text(
                                '${DateTime.tryParse(row['created_at'] as String)?.toLocal()} · ${row['data']['share_with_care_team'] == true ? 'Shared' : 'Private'}'),
                            children: [
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child:
                                  Text(row['data']['original_text'] as String))
                        ]))
                ])),
            ListView(padding: const EdgeInsets.all(20), children: [
              Text('The whole month, clearly seen',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Text(
                  'Counts reflect confirmed reports. AI narrative is a draft for review; the source reports remain available.'),
              TextField(
                  controller: _month,
                  decoration:
                      const InputDecoration(labelText: 'Month (YYYY-MM)')),
              const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                FilledButton(
                    onPressed: _busy ? null : () => _summarize(),
                    child: const Text('View patterns')),
                TextButton(
                    onPressed:
                        _busy || !_consent ? null : () => _summarize(ai: true),
                    child: const Text('Prepare AI handoff'))
              ]),
              if (_summary != null) ...[
                const SizedBox(height: 16),
                Text(
                    '${_summary!['report_count']} confirmed reports · ${_summary!['urgent_report_count']} urgent flags'),
                for (final item
                    in (_summary!['patterns'] as List? ?? []).whereType<Map>())
                  Card(
                      child: ExpansionTile(
                          title: Text(
                              '${item['name']} · ${item['count']} reports'),
                          subtitle: Text(
                              'Reported severity: ${item['reported_severity_change']}'),
                          children: [
                        for (final occurrence
                            in (item['occurrences'] as List).whereType<Map>())
                          ListTile(
                              title: Text(
                                  '${occurrence['reported_at']} · ${occurrence['severity']}'),
                              subtitle: Text(
                                  '${occurrence['onset']} · ${occurrence['frequency']}'))
                      ])),
                for (final insight in (_summary!['ai_insights'] as List? ?? [])
                    .whereType<Map>())
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              '${insight['text']}\nSources: ${(insight['source_report_ids'] as List).join(', ')}'))),
                Text(_summary!['notice'] as String? ?? '')
              ]
            ]),
          ]))
        ]),
      ));
}
