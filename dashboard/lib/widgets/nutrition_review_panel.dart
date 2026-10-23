import 'package:flutter/material.dart';
import '../core/api_client.dart';

class NutritionReviewPanel extends StatefulWidget {
  const NutritionReviewPanel(
      {super.key,
      required this.api,
      required this.hospitalId,
      required this.patientId});
  final ApiClient api;
  final String hospitalId, patientId;
  @override
  State<NutritionReviewPanel> createState() => _NutritionReviewPanelState();
}

class _NutritionReviewPanelState extends State<NutritionReviewPanel> {
  Future<Map<String, dynamic>>? _data;
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _data = widget.api.patientNutrition(widget.hospitalId, widget.patientId);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _review(String id, String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.reviewNutrition(
          widget.hospitalId, widget.patientId, id, action, _note.text.trim());
      if (mounted) {
        setState(() => _data =
            widget.api.patientNutrition(widget.hospitalId, widget.patientId));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reports and nutrition review',
                style: Theme.of(context).textTheme.titleLarge),
            const Text(
                'Patient-confirmed values and rule comparisons require clinical interpretation. Meal drafts have example portions and no validated nutrient prescription.'),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            FutureBuilder<Map<String, dynamic>>(
                future: _data,
                builder: (c, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                        'Nutrition review unavailable: ${snapshot.error}');
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final data = snapshot.data!;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final row
                            in (data['reports'] as List).whereType<Map>())
                          ExpansionTile(
                              title: Text(row['data']['title'] as String),
                              subtitle: Text(row['data']['analysis']
                                  ['conclusion'] as String),
                              children: [
                                for (final reading in (row['data']['analysis']
                                        ['readings'] as List)
                                    .whereType<Map>())
                                  ListTile(
                                      title: Text(
                                          '${reading['name']} · ${reading['value']} ${reading['unit']}'),
                                      subtitle: Text(
                                          '${reading['status']}\n${reading['comparison']}\n${reading['explanation']}\n${reading['source_quote']}'))
                              ]),
                        for (final row
                            in (data['plans'] as List).whereType<Map>())
                          ExpansionTile(
                              title: Text(row['data']['title'] as String),
                              subtitle: Text(row['data']['status'] as String),
                              children: [
                                Text(
                                    'Declared preferences: ${row['data']['preferences']}'),
                                for (final day in (row['data']['days'] as List)
                                    .whereType<Map>())
                                  ListTile(
                                      title: Text(day['date'] as String),
                                      subtitle: Text((day['meals'] as List)
                                          .map((m) =>
                                              '${m['slot']}: ${m['name']} · ${m['portion']}\nIngredients: ${(m['ingredients'] as List).join(', ')}')
                                          .join('\n'))),
                                TextField(
                                    controller: _note,
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Clinical review note (required)')),
                                Wrap(spacing: 12, children: [
                                  FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _review(
                                              row['id'] as String, 'approve'),
                                      child:
                                          const Text('Approve reviewed plan')),
                                  OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _review(row['id'] as String,
                                              'request_changes'),
                                      child: const Text('Request changes'))
                                ]),
                              ]),
                      ]);
                })
          ])));
}
