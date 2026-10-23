import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/patient_api.dart';
import 'food_art.dart';

const _cream = Color(0xffFFF9F1);
const _ink = Color(0xff463E35);
const _sage = Color(0xff617E65);

class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key, required this.api});
  final PatientApi api;
  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  Map<String, dynamic> _home = {};
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>>? _draft;
  String? _reportId, _error, _notice;
  String _stage = 'pregnant', _protocol = 'unknown';
  int? _trimester;
  bool _busy = false, _consent = false, _foodConsent = false;
  final _text = TextEditingController();
  Map<String, dynamic>? get _plan => _home['plan'] is Map
      ? Map<String, dynamic>.from(_home['plan'] as Map)
      : null;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.api.nutrition(),
        widget.api.reportAnalyses(),
      ]);
      if (!mounted) return;
      setState(() {
        _home = values[0];
        _reports = (values[1]['items'] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _reportId ??= _reports.isEmpty ? null : _reports.first['id'] as String;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
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

  Future<void> _extract(bool file) => _run(() async {
    if (!_consent) {
      throw StateError(
        'Allow report processing first, or enter values yourself.',
      );
    }
    Map<String, dynamic> result;
    if (file) {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (selected == null) return;
      if (await selected.length() > 3800000) {
        throw StateError('Choose a PDF or image under 3.8 MB.');
      }
      result = await widget.api.extractReportFile(
        await selected.readAsBytes(),
        selected.name,
      );
    } else {
      result = await widget.api.extractReportText(_text.text.trim());
    }
    if (!mounted) return;
    final draft = result['draft'] as Map;
    setState(() {
      _draft = (draft['readings'] as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      _protocol = draft['protocol'] as String? ?? 'unknown';
      _notice = result['notice'] as String?;
    });
  });
  Map<String, dynamic> _emptyReading() => {
    'analyte': 'other',
    'name': '',
    'value': null,
    'unit': '',
    'reference_min': null,
    'reference_max': null,
    'reference_scope': 'unspecified',
    'reference_trimester': null,
    'source_quote': '',
    'uncertain': true,
  };
  Future<void> _confirm() => _run(() async {
    final result = await widget.api.confirmReport({
      'confirmed': true,
      'title': 'Report · ${DateTime.now().toString().substring(0, 10)}',
      'readings': _draft,
      'context': {
        'stage': _stage,
        'trimester': _trimester,
        'protocol': _protocol,
      },
    });
    if (!mounted) return;
    setState(() {
      _reportId = result['report']['id'] as String;
      _draft = null;
      _notice =
          'Report saved. Review the comparisons below, then request AI food suggestions based on your preferences.';
    });
    await _load();
  });
  Future<void> _generate() => _run(() async {
    if (_reportId == null) {
      throw StateError('Confirm a medical report first in the Reports tab.');
    }
    await widget.api.analyseFoods(_reportId!);
    await _load();
  });
  Future<void> _preferences() async {
    final prefs = Map<String, dynamic>.from(_home['preferences'] as Map? ?? {});
    String diet = prefs['diet'] as String? ?? 'vegetarian';
    String? sweet = prefs['sweet_preference'] as String?,
        appetite = prefs['appetite'] as String?,
        spice = prefs['spice_preference'] as String?;
    bool? sickness = prefs['morning_sickness'] as bool?;
    var confirmed = prefs['allergies_confirmed'] == true;
    final allergens = Set<String>.from(prefs['allergens'] as List? ?? []);
    final inputs = {
      for (final key in [
        'dislikes',
        'favourite_foods',
        'other_allergies',
        'other_preferences',
        'care_team_instructions',
      ])
        key: TextEditingController(
          text: prefs[key] is List
              ? (prefs[key] as List).join(', ')
              : prefs[key]?.toString() ?? '',
        ),
    };
    String? formError;
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.viewInsetsOf(c).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Let’s get to know your food preferences',
                    style: Theme.of(c).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A few details help us suggest foods that fit your tastes, symptoms and confirmed report.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: diet,
                    decoration: const InputDecoration(
                      labelText: 'How do you usually eat?',
                    ),
                    items: [
                      for (final entry in const {
                        'vegetarian': 'Vegetarian',
                        'vegan': 'Vegan',
                        'non_vegetarian': 'Non-vegetarian',
                        'eggetarian': 'Vegetarian + eggs',
                        'pescatarian': 'Vegetarian + fish',
                        'other': 'Something else',
                      }.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (v) => update(() => diet = v!),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: sweet,
                    decoration: const InputDecoration(
                      labelText: 'Do you enjoy sweet foods?',
                    ),
                    items: [
                      for (final e in const {
                        'yes': 'Yes, I have a sweet tooth',
                        'sometimes': 'Sometimes',
                        'no': 'Not usually',
                      }.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => sweet = v),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<bool>(
                    initialValue: sickness,
                    decoration: const InputDecoration(
                      labelText: 'Morning sickness or nausea?',
                    ),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Yes')),
                      DropdownMenuItem(value: false, child: Text('No')),
                    ],
                    onChanged: (v) => update(() => sickness = v),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: appetite,
                    decoration: const InputDecoration(
                      labelText: 'How is your appetite?',
                    ),
                    items: [
                      for (final e in const {
                        'low': 'Lower than usual',
                        'usual': 'Usual',
                        'high': 'More hungry than usual',
                      }.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => appetite = v),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: spice,
                    decoration: const InputDecoration(
                      labelText: 'How spicy do you like food?',
                    ),
                    items: [
                      for (final e in const {
                        'mild': 'Mild',
                        'medium': 'Medium',
                        'spicy': 'Spicy',
                      }.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => spice = v),
                  ),
                  for (final pair in [
                    ('favourite_foods', 'Foods you enjoy (comma separated)'),
                    (
                      'dislikes',
                      'Ingredients you dislike or avoid (comma separated)',
                    ),
                    ('other_preferences', 'Anything else about how you eat?'),
                  ]) ...[
                    const SizedBox(height: 18),
                    TextField(
                      controller: inputs[pair.$1],
                      maxLength: 500,
                      decoration: InputDecoration(labelText: pair.$2),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Allergies & intolerances',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value
                          in (_home['allergens'] as List? ?? []).cast<String>())
                        FilterChip(
                          label: Text(value.replaceAll('_', ' ')),
                          selected: allergens.contains(value),
                          onSelected: (v) => update(
                            () => v
                                ? allergens.add(value)
                                : allergens.remove(value),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: inputs['other_allergies'],
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Any other allergy? Leave blank if none',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: inputs['care_team_instructions'],
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText:
                          'Food instructions from your care team (optional)',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I have checked my allergies and preferences',
                    ),
                    value: confirmed,
                    onChanged: (v) => update(() => confirmed = v ?? false),
                  ),
                  if (formError != null)
                    Text(
                      formError!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                  FilledButton(
                    onPressed: () {
                      if (sweet == null ||
                          sickness == null ||
                          appetite == null ||
                          spice == null ||
                          !confirmed ||
                          diet == 'other' &&
                              inputs['other_preferences']!.text
                                  .trim()
                                  .isEmpty) {
                        update(
                          () => formError =
                              'Please answer the questions and confirm your allergy information.',
                        );
                        return;
                      }
                      Navigator.pop(c, true);
                    },
                    child: const Text('Save my preferences'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (save == true) {
      await _run(() async {
        await widget.api.nutritionPreferences({
          'diet': diet,
          'allergens': allergens.toList(),
          'allergies_confirmed': confirmed,
          'sweet_preference': sweet,
          'morning_sickness': sickness,
          'appetite': appetite,
          'spice_preference': spice,
          for (final key in ['dislikes', 'favourite_foods'])
            key: inputs[key]!.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          for (final key in [
            'other_allergies',
            'other_preferences',
            'care_team_instructions',
          ])
            key: inputs[key]!.text.trim(),
        });
        await _load();
      });
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final input in inputs.values) {
        input.dispose();
      }
    });
  }

  Widget _foodPlan() {
    final saved = _plan?['data'] as Map?;
    final data = saved?['report_id'] == _reportId ? saved : null;
    final complete = _home['profile_complete'] == true;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Food that fits you',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: _ink),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tell us what you enjoy and how you feel. AI will consider your preferences and confirmed report before suggesting foods and what to limit or avoid.',
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: Icon(
              complete ? Icons.check_circle_outline : Icons.restaurant_menu,
              color: _sage,
            ),
            title: Text(
              complete
                  ? 'Your preferences are saved'
                  : 'Start with your food preferences',
            ),
            subtitle: const Text(
              'Tastes, nausea, appetite, allergies and foods to avoid',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _preferences,
          ),
        ),
        if (complete) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_reportId),
            initialValue: _reportId,
            decoration: const InputDecoration(
              labelText: 'Use this confirmed report',
            ),
            items: [
              for (final r in _reports)
                DropdownMenuItem(
                  value: r['id'] as String,
                  child: Text(
                    r['data']['title'] as String? ?? 'My report',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy ? null : (v) => setState(() => _reportId = v),
          ),
          if (_reports.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Add and confirm a report in the Reports tab first.'),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Allow AI to analyse my selected report and food preferences',
            ),
            value: _foodConsent,
            onChanged: _busy
                ? null
                : (v) => setState(() => _foodConsent = v ?? false),
          ),
          FilledButton.icon(
            onPressed: _busy || !_foodConsent || _reportId == null
                ? null
                : _generate,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Analyse & suggest foods'),
          ),
        ],
        if (_home['requires_refresh'] == true)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Your preferences changed. Analyse again for updated suggestions.',
            ),
          ),
        if (data != null) ...[
          const SizedBox(height: 24),
          Text(
            data['overview'] as String,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            data['notice'] as String,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (data['review_note'] != null)
            Text('Care team: ${data['review_note']}'),
          for (final group in [
            ('suggest', 'Foods to try', const Color(0xffE5EFE2)),
            ('limit', 'Have less often', const Color(0xffFFF0D5)),
            ('avoid', 'Avoid for now', const Color(0xffFBE5DF)),
          ]) ...[
            const SizedBox(height: 22),
            Text(group.$2, style: Theme.of(context).textTheme.titleLarge),
            for (final food in (data['foods'] as List).whereType<Map>().where(
              (f) => f['advice'] == group.$1,
            ))
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: group.$3,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FoodArt(
                      kind: food['art'] as String,
                      label: food['name'] as String,
                      size: 72,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            food['name'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(food['reason'] as String),
                          if ((food['preparation'] as String? ?? '').isNotEmpty)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text('Ingredients & preparation'),
                              children: [
                                Text(
                                  '${(food['ingredients'] as List? ?? []).join(', ')}\n${food['preparation']}',
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if ((data['discussion_points'] as List? ?? []).isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Discuss with your care team',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final point in data['discussion_points'] as List)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('• $point'),
              ),
          ],
        ],
      ],
    );
  }

  Widget _readingEditor(Map<String, dynamic> row, int i) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reading ${i + 1}${row['uncertain'] == true ? ' · check carefully' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Remove reading',
                onPressed: () => setState(() => _draft!.removeAt(i)),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: row['analyte'] as String,
            decoration: const InputDecoration(labelText: 'Test / timepoint'),
            items: [
              for (final value in [
                'ogtt_fasting',
                'ogtt_1h',
                'ogtt_2h',
                'hemoglobin',
                'tsh',
                'free_t4',
                'other',
              ])
                DropdownMenuItem(
                  value: value,
                  child: Text(value.replaceAll('_', ' ')),
                ),
            ],
            onChanged: (v) => row['analyte'] = v,
          ),
          TextFormField(
            initialValue: row['name'] as String,
            decoration: const InputDecoration(labelText: 'Printed test name'),
            onChanged: (v) => row['name'] = v,
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: row['value']?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Value'),
                  onChanged: (v) => row['value'] = double.tryParse(v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: row['unit'] as String,
                  decoration: const InputDecoration(
                    labelText: 'Unit exactly as printed',
                  ),
                  onChanged: (v) => row['unit'] = v,
                ),
              ),
            ],
          ),
          Row(
            children: [
              for (final field in ['reference_min', 'reference_max'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextFormField(
                      initialValue: row[field]?.toString() ?? '',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: field == 'reference_min'
                            ? 'Range minimum'
                            : 'Range maximum',
                      ),
                      onChanged: (v) => row[field] = double.tryParse(v),
                    ),
                  ),
                ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: row['reference_scope'] as String? ?? 'unspecified',
            decoration: const InputDecoration(
              labelText: 'Printed range applies to',
            ),
            items: const [
              DropdownMenuItem(
                value: 'unspecified',
                child: Text('Unspecified / adult'),
              ),
              DropdownMenuItem(
                value: 'pregnancy',
                child: Text('Pregnancy-specific'),
              ),
              DropdownMenuItem(
                value: 'trimester',
                child: Text('Trimester-specific'),
              ),
            ],
            onChanged: (v) => row['reference_scope'] = v,
          ),
          DropdownButtonFormField<int>(
            initialValue: row['reference_trimester'] as int?,
            decoration: const InputDecoration(
              labelText: 'Trimester printed beside range (if any)',
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1')),
              DropdownMenuItem(value: 2, child: Text('2')),
              DropdownMenuItem(value: 3, child: Text('3')),
            ],
            onChanged: (v) => row['reference_trimester'] = v,
          ),
          if ((row['source_quote'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Printed evidence: ${row['source_quote']}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _reportView() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Understand what is on the page.',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Upload a report or paste its text. Check every value and unit before comparison; AI can misread a report.',
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Allow AI processing of this medical report'),
        subtitle: const Text(
          'The report is sent to the AI provider. This extraction route does not retain the file; confirmed values are stored.',
        ),
        value: _consent,
        onChanged: (v) => setState(() => _consent = v ?? false),
      ),
      FilledButton.icon(
        onPressed: _busy || !_consent ? null : () => _extract(true),
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Choose PDF or photo'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _text,
        maxLength: 16000,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'Or paste report text',
          border: OutlineInputBorder(),
        ),
      ),
      Wrap(
        spacing: 12,
        children: [
          TextButton(
            onPressed: _busy || !_consent ? null : () => _extract(false),
            child: const Text('Extract readings'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _draft = [_emptyReading()]),
            child: const Text('Enter values myself'),
          ),
        ],
      ),
      if (_notice != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_notice!),
        ),
      if (_draft != null) ...[
        Text(
          'Confirm context and readings',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        DropdownButtonFormField<String>(
          initialValue: _stage,
          decoration: const InputDecoration(
            labelText: 'Patient stage for this report',
          ),
          items: const [
            DropdownMenuItem(value: 'pregnant', child: Text('Pregnant')),
            DropdownMenuItem(value: 'postpartum', child: Text('Postpartum')),
            DropdownMenuItem(
              value: 'not_recorded',
              child: Text('Not recorded'),
            ),
          ],
          onChanged: (v) => setState(() => _stage = v!),
        ),
        DropdownButtonFormField<int>(
          initialValue: _trimester,
          decoration: const InputDecoration(
            labelText: 'Trimester at test date (leave unknown if unsure)',
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('First')),
            DropdownMenuItem(value: 2, child: Text('Second')),
            DropdownMenuItem(value: 3, child: Text('Third')),
          ],
          onChanged: (v) => _trimester = v,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(_protocol),
          initialValue: _protocol,
          decoration: const InputDecoration(labelText: 'Glucose test protocol'),
          items: const [
            DropdownMenuItem(
              value: 'unknown',
              child: Text('Unknown / not applicable'),
            ),
            DropdownMenuItem(
              value: '75g_ogtt_fasting',
              child: Text('Confirmed fasting 75 g OGTT'),
            ),
            DropdownMenuItem(value: 'other', child: Text('Other protocol')),
          ],
          onChanged: (v) => _protocol = v!,
        ),
        for (var i = 0; i < _draft!.length; i++) _readingEditor(_draft![i], i),
        TextButton.icon(
          onPressed: () => setState(() => _draft!.add(_emptyReading())),
          icon: const Icon(Icons.add),
          label: const Text('Add another reading'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: const Text('I checked these values • compare and save'),
        ),
      ],
      const SizedBox(height: 24),
      Text(
        'Your confirmed reports',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      for (final row in _reports)
        Card(
          child: ExpansionTile(
            title: Text(row['data']['title'] as String),
            subtitle: Text(row['data']['analysis']['conclusion'] as String),
            children: [
              for (final reading
                  in (row['data']['analysis']['readings'] as List)
                      .whereType<Map>())
                ListTile(
                  title: Text(
                    '${reading['name']}: ${reading['value']} ${reading['unit']}',
                  ),
                  subtitle: Text(
                    '${(reading['status'] as String).replaceAll('_', ' ')}\n${reading['comparison'] ?? ''}\n${reading['explanation']}\nSource: ${reading['source'] ?? 'not available'}',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(row['data']['analysis']['notice'] as String),
              ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        title: const Text('Nourish'),
        actions: [
          IconButton(
            tooltip: 'Food preferences',
            onPressed: _preferences,
            icon: const Icon(Icons.tune),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Food ideas'),
            Tab(text: 'Reports'),
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
          Expanded(child: TabBarView(children: [_foodPlan(), _reportView()])),
        ],
      ),
    ),
  );
}
