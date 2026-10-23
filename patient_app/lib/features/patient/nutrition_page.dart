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
  int _day = 0;
  bool _busy = false, _consent = false;
  final _text = TextEditingController();
  final _checked = <String>{};
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
      final values = await Future.wait(
          [widget.api.nutrition(), widget.api.reportAnalyses()]);
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
              'Allow report processing first, or enter values yourself.');
        }
        Map<String, dynamic> result;
        if (file) {
          final selected = await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg']);
          if (selected == null) return;
          if (await selected.length() > 3800000) {
            throw StateError('Choose a PDF or image under 3.8 MB.');
          }
          result = await widget.api
              .extractReportFile(await selected.readAsBytes(), selected.name);
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
        'uncertain': true
      };
  Future<void> _confirm() => _run(() async {
        final result = await widget.api.confirmReport({
          'confirmed': true,
          'title': 'Report · ${DateTime.now().toString().substring(0, 10)}',
          'readings': _draft,
          'context': {
            'stage': _stage,
            'trimester': _trimester,
            'protocol': _protocol
          }
        });
        if (!mounted) return;
        setState(() {
          _reportId = result['report']['id'] as String;
          _draft = null;
          _notice =
              'Report saved. Review the comparisons below, then prepare your meal-plan draft.';
        });
        await _load();
      });
  Future<void> _generate() => _run(() async {
        if (_reportId == null) {
          throw StateError(
              'Confirm a medical report first in the Reports tab.');
        }
        await widget.api.createMealPlan(_reportId!);
        await _load();
      });
  Future<void> _preferences() async {
    final prefs = Map<String, dynamic>.from(_home['preferences'] as Map? ?? {});
    var diet = prefs['diet'] as String? ?? 'vegetarian';
    final allergens = Set<String>.from(prefs['allergens'] as List? ?? []);
    final dislikes = TextEditingController(
        text: (prefs['dislikes'] as List? ?? []).join(', '));
    var confirmed = prefs['allergies_confirmed'] == true;
    final save = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (c) => StatefulBuilder(
            builder: (c, update) => SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(
                            24, 24, 24, 24 + MediaQuery.viewInsetsOf(c).bottom),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Made around your needs',
                                  style: Theme.of(c).textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              const Text(
                                  'Choose food preferences and allergies. If you have an unlisted allergy, a therapeutic diet, or other restrictions, ask your dietitian for an individual plan.'),
                              DropdownButtonFormField<String>(
                                  initialValue: diet,
                                  decoration: const InputDecoration(
                                      labelText: 'Food preference'),
                                  items: [
                                    for (final value in [
                                      'vegetarian',
                                      'vegan',
                                      'non_vegetarian'
                                    ])
                                      DropdownMenuItem(
                                          value: value,
                                          child:
                                              Text(value.replaceAll('_', ' ')))
                                  ],
                                  onChanged: (v) => update(() => diet = v!)),
                              const SizedBox(height: 16),
                              Text('Food allergies / intolerances',
                                  style: Theme.of(c).textTheme.titleMedium),
                              Wrap(spacing: 8, children: [
                                for (final value
                                    in (_home['allergens'] as List? ?? [])
                                        .cast<String>())
                                  FilterChip(
                                      label: Text(value.replaceAll('_', ' ')),
                                      selected: allergens.contains(value),
                                      onSelected: (v) => update(() => v
                                          ? allergens.add(value)
                                          : allergens.remove(value)))
                              ]),
                              TextField(
                                  controller: dislikes,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Ingredients to avoid (comma separated)')),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                      'I have checked these food allergies and preferences'),
                                  value: confirmed,
                                  onChanged: (v) =>
                                      update(() => confirmed = v ?? false)),
                              FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Save preferences')),
                            ]))))));
    if (save == true) {
      await _run(() async {
        await widget.api.nutritionPreferences({
          'diet': diet,
          'allergens': allergens.toList(),
          'dislikes': dislikes.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          'allergies_confirmed': confirmed
        });
        await _load();
      });
    }
    Future<void>.delayed(const Duration(seconds: 1), dislikes.dispose);
  }

  Future<void> _swap(Map meal) async {
    final prefs = Map<String, dynamic>.from(_home['preferences'] as Map? ?? {});
    final options =
        (_home['catalog'] as List? ?? []).whereType<Map>().where((item) {
      if (item['slot'] != meal['slot'] || item['id'] == meal['id']) {
        return false;
      }
      if ((item['allergens'] as List)
          .any((a) => (prefs['allergens'] as List? ?? []).contains(a))) {
        return false;
      }
      if (prefs['diet'] == 'vegan' && item['diet'] != 'vegan' ||
          prefs['diet'] == 'vegetarian' && item['diet'] == 'non_vegetarian') {
        return false;
      }
      return true;
    }).toList();
    final replacement = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
                child: ListView(padding: const EdgeInsets.all(20), children: [
              Text('Something else sounds good?',
                  style: Theme.of(c).textTheme.titleLarge),
              const Text(
                  'Changing an approved meal returns the plan to draft for review.'),
              if (options.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                        'No alternative in this catalog fits these restrictions. Ask your dietitian.')),
              for (final option in options)
                ListTile(
                    leading: FoodArt(
                        kind: option['art'] as String,
                        label: option['name'] as String,
                        size: 56),
                    title: Text(option['name'] as String),
                    subtitle: Text(option['portion'] as String),
                    onTap: () => Navigator.pop(c, option['id'] as String))
            ])));
    if (replacement != null) {
      await _run(() async {
        await widget.api.changeMeal(_plan!['id'] as String,
            {'day': _day, 'slot': meal['slot'], 'swap_to': replacement});
        await _load();
      });
    }
  }

  Widget _mealCard(Map meal) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xffEDE3D7))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((meal['slot'] as String).replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                color: _sage,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          FoodArt(kind: meal['art'] as String, label: meal['name'] as String),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(meal['name'] as String,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: _ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(meal['portion'] as String,
                    style:
                        const TextStyle(color: Color(0xff776D60), fontSize: 13))
              ]))
        ]),
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Ingredients & preparation',
                style: TextStyle(fontSize: 13)),
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text((meal['ingredients'] as List).join(', '))),
              const SizedBox(height: 6),
              Text(meal['preparation'] as String)
            ]),
        Row(children: [
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _swap(meal),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Swap meal')),
          const Spacer(),
          Checkbox(
              value: meal['completed'] == true,
              onChanged: _busy
                  ? null
                  : (value) => _run(() async {
                        await widget.api.changeMeal(_plan!['id'] as String, {
                          'day': _day,
                          'slot': meal['slot'],
                          'completed': value
                        });
                        await _load();
                      })),
          const Text('Had this')
        ]),
      ]));

  Widget _foodPlan() {
    final plan = _plan;
    final data = plan == null ? null : plan['data'] as Map;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xffF3E5D0), Color(0xffE8EDDC)]),
              borderRadius: BorderRadius.circular(30)),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('NOURISH & NURTURE',
                      style: TextStyle(
                          color: _sage,
                          letterSpacing: 2,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text('A little care,\none meal at a time.',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: _ink, height: 1.2)),
                  const SizedBox(height: 12),
                  const Text(
                      'Familiar food. Gentle routines.\nShaped around your preferences.',
                      style: TextStyle(color: Color(0xff776D60), fontSize: 13))
                ])),
            const FoodArt(
                kind: 'salad', label: 'a balanced vegetable bowl', size: 108)
          ])),
      const SizedBox(height: 18),
      Wrap(spacing: 10, runSpacing: 8, children: [
        ActionChip(
            avatar: const Icon(Icons.tune, size: 18),
            label: const Text('Food preferences'),
            onPressed: _preferences),
        const Chip(
            avatar: Icon(Icons.spa_outlined, size: 18),
            label: Text('Pregnancy food safety'))
      ]),
      if (_reports.isNotEmpty)
        DropdownButtonFormField<String>(
            initialValue: _reportId,
            decoration:
                const InputDecoration(labelText: 'Use this confirmed report'),
            items: [
              for (final report in _reports)
                DropdownMenuItem(
                    value: report['id'] as String,
                    child: Text(report['data']['title'] as String,
                        overflow: TextOverflow.ellipsis))
            ],
            onChanged: (v) => setState(() => _reportId = v)),
      const SizedBox(height: 12),
      FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.auto_awesome_outlined),
          label:
              Text(plan == null ? 'Prepare my week' : 'Create a fresh plan')),
      if (plan == null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(_home['requires_refresh'] == true
                ? 'Your preferences changed. Create a fresh plan before using the previous meals.'
                : 'Start with a confirmed report in the Reports tab, then check your food preferences. Your plan will appear here.')),
      if (data != null) ...[
        const SizedBox(height: 18),
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: data['status'] == 'clinician_approved'
                    ? const Color(0xffE5EFE2)
                    : const Color(0xffF6E9D8),
                borderRadius: BorderRadius.circular(18)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((data['status'] as String).replaceAll('_', ' '),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(data['notice'] as String,
                  style: const TextStyle(fontSize: 12)),
              if (data['review_note'] != null)
                Text('Care team: ${data['review_note']}')
            ])),
        const SizedBox(height: 20),
        SizedBox(
            height: 48,
            child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                separatorBuilder: (_, i) => const SizedBox(width: 8),
                itemBuilder: (c, i) {
                  final date =
                      DateTime.parse(data['days'][i]['date'] as String);
                  return ChoiceChip(
                      label: Text('${[
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun'
                      ][date.weekday - 1]} ${date.day}'),
                      selected: _day == i,
                      onSelected: (_) => setState(() => _day = i));
                })),
        const SizedBox(height: 16),
        for (final meal
            in (data['days'][_day]['meals'] as List).whereType<Map>())
          _mealCard(meal),
        const SizedBox(height: 12),
        Text('A few food-safety basics',
            style: Theme.of(context).textTheme.titleMedium),
        for (final note in (data['food_safety'] as List))
          Padding(
              padding: const EdgeInsets.only(top: 8), child: Text('• $note')),
      ]
    ]);
  }

  Widget _readingEditor(Map<String, dynamic> row, int i) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: Text(
                      'Reading ${i + 1}${row['uncertain'] == true ? ' · check carefully' : ''}',
                      style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                  tooltip: 'Remove reading',
                  onPressed: () => setState(() => _draft!.removeAt(i)),
                  icon: const Icon(Icons.close))
            ]),
            DropdownButtonFormField<String>(
                initialValue: row['analyte'] as String,
                decoration:
                    const InputDecoration(labelText: 'Test / timepoint'),
                items: [
                  for (final value in [
                    'ogtt_fasting',
                    'ogtt_1h',
                    'ogtt_2h',
                    'hemoglobin',
                    'tsh',
                    'free_t4',
                    'other'
                  ])
                    DropdownMenuItem(
                        value: value, child: Text(value.replaceAll('_', ' ')))
                ],
                onChanged: (v) => row['analyte'] = v),
            TextFormField(
                initialValue: row['name'] as String,
                decoration:
                    const InputDecoration(labelText: 'Printed test name'),
                onChanged: (v) => row['name'] = v),
            Row(children: [
              Expanded(
                  child: TextFormField(
                      initialValue: row['value']?.toString() ?? '',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Value'),
                      onChanged: (v) => row['value'] = double.tryParse(v))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextFormField(
                      initialValue: row['unit'] as String,
                      decoration: const InputDecoration(
                          labelText: 'Unit exactly as printed'),
                      onChanged: (v) => row['unit'] = v))
            ]),
            Row(children: [
              for (final field in ['reference_min', 'reference_max'])
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextFormField(
                            initialValue: row[field]?.toString() ?? '',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: field == 'reference_min'
                                    ? 'Range minimum'
                                    : 'Range maximum'),
                            onChanged: (v) => row[field] = double.tryParse(v))))
            ]),
            DropdownButtonFormField<String>(
                initialValue:
                    row['reference_scope'] as String? ?? 'unspecified',
                decoration: const InputDecoration(
                    labelText: 'Printed range applies to'),
                items: const [
                  DropdownMenuItem(
                      value: 'unspecified', child: Text('Unspecified / adult')),
                  DropdownMenuItem(
                      value: 'pregnancy', child: Text('Pregnancy-specific')),
                  DropdownMenuItem(
                      value: 'trimester', child: Text('Trimester-specific'))
                ],
                onChanged: (v) => row['reference_scope'] = v),
            DropdownButtonFormField<int>(
                initialValue: row['reference_trimester'] as int?,
                decoration: const InputDecoration(
                    labelText: 'Trimester printed beside range (if any)'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3'))
                ],
                onChanged: (v) => row['reference_trimester'] = v),
            if ((row['source_quote'] as String? ?? '').isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Printed evidence: ${row['source_quote']}',
                      style: const TextStyle(fontSize: 12))),
          ])));

  Widget _reportView() =>
      ListView(padding: const EdgeInsets.all(20), children: [
        Text('Understand what is on the page.',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
            'Upload a report or paste its text. Check every value and unit before comparison; AI can misread a report.'),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow AI processing of this medical report'),
            subtitle: const Text(
                'The report is sent to the AI provider. This extraction route does not retain the file; confirmed values are stored.'),
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false)),
        FilledButton.icon(
            onPressed: _busy || !_consent ? null : () => _extract(true),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Choose PDF or photo')),
        const SizedBox(height: 12),
        TextField(
            controller: _text,
            maxLength: 16000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
                labelText: 'Or paste report text',
                border: OutlineInputBorder())),
        Wrap(spacing: 12, children: [
          TextButton(
              onPressed: _busy || !_consent ? null : () => _extract(false),
              child: const Text('Extract readings')),
          TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _draft = [_emptyReading()]),
              child: const Text('Enter values myself'))
        ]),
        if (_notice != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_notice!)),
        if (_draft != null) ...[
          Text('Confirm context and readings',
              style: Theme.of(context).textTheme.titleLarge),
          DropdownButtonFormField<String>(
              initialValue: _stage,
              decoration: const InputDecoration(
                  labelText: 'Patient stage for this report'),
              items: const [
                DropdownMenuItem(value: 'pregnant', child: Text('Pregnant')),
                DropdownMenuItem(
                    value: 'postpartum', child: Text('Postpartum')),
                DropdownMenuItem(
                    value: 'not_recorded', child: Text('Not recorded'))
              ],
              onChanged: (v) => setState(() => _stage = v!)),
          DropdownButtonFormField<int>(
              initialValue: _trimester,
              decoration: const InputDecoration(
                  labelText:
                      'Trimester at test date (leave unknown if unsure)'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('First')),
                DropdownMenuItem(value: 2, child: Text('Second')),
                DropdownMenuItem(value: 3, child: Text('Third'))
              ],
              onChanged: (v) => _trimester = v),
          DropdownButtonFormField<String>(
              key: ValueKey(_protocol),
              initialValue: _protocol,
              decoration:
                  const InputDecoration(labelText: 'Glucose test protocol'),
              items: const [
                DropdownMenuItem(
                    value: 'unknown', child: Text('Unknown / not applicable')),
                DropdownMenuItem(
                    value: '75g_ogtt_fasting',
                    child: Text('Confirmed fasting 75 g OGTT')),
                DropdownMenuItem(value: 'other', child: Text('Other protocol'))
              ],
              onChanged: (v) => _protocol = v!),
          for (var i = 0; i < _draft!.length; i++)
            _readingEditor(_draft![i], i),
          TextButton.icon(
              onPressed: () => setState(() => _draft!.add(_emptyReading())),
              icon: const Icon(Icons.add),
              label: const Text('Add another reading')),
          FilledButton(
              onPressed: _busy ? null : _confirm,
              child: const Text('I checked these values • compare and save')),
        ],
        const SizedBox(height: 24),
        Text('Your confirmed reports',
            style: Theme.of(context).textTheme.titleLarge),
        for (final row in _reports)
          Card(
              child: ExpansionTile(
                  title: Text(row['data']['title'] as String),
                  subtitle:
                      Text(row['data']['analysis']['conclusion'] as String),
                  children: [
                for (final reading
                    in (row['data']['analysis']['readings'] as List)
                        .whereType<Map>())
                  ListTile(
                      title: Text(
                          '${reading['name']}: ${reading['value']} ${reading['unit']}'),
                      subtitle: Text(
                          '${(reading['status'] as String).replaceAll('_', ' ')}\n${reading['comparison'] ?? ''}\n${reading['explanation']}\nSource: ${reading['source'] ?? 'not available'}')),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(row['data']['analysis']['notice'] as String))
              ])),
      ]);

  Widget _shopping() {
    final data = _plan?['data'] as Map?;
    final items = <String>{};
    if (data != null) {
      for (final day in (data['days'] as List).whereType<Map>()) {
        for (final meal in (day['meals'] as List).whereType<Map>()) {
          items.addAll((meal['ingredients'] as List).cast<String>());
        }
      }
    }
    final sorted = items.toList()..sort();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('A simple list for your week',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
          'Ingredients from your current plan. Quantities depend on the portions you agree with your dietitian. Checkmarks last for this screen session.'),
      const SizedBox(height: 20),
      if (sorted.isEmpty)
        const Text('Prepare a meal plan to see your ingredients.'),
      for (final item in sorted)
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item),
            value: _checked.contains(item),
            onChanged: (v) => setState(
                () => v == true ? _checked.add(item) : _checked.remove(item)))
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 3,
      child: Scaffold(
          backgroundColor: _cream,
          appBar: AppBar(
              backgroundColor: _cream,
              title: const Text('Nourish'),
              actions: [
                IconButton(
                    tooltip: 'Food preferences',
                    onPressed: _preferences,
                    icon: const Icon(Icons.tune))
              ],
              bottom: const TabBar(tabs: [
                Tab(text: 'Your week'),
                Tab(text: 'Reports'),
                Tab(text: 'Shopping list')
              ])),
          body: Column(children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xffA13734)))),
            Expanded(
                child: TabBarView(
                    children: [_foodPlan(), _reportView(), _shopping()]))
          ])));
}
