import 'package:flutter/material.dart';
import '../core/api_client.dart';

class ConcernSummaryPanel extends StatefulWidget {
  const ConcernSummaryPanel(
      {super.key,
      required this.api,
      required this.hospitalId,
      required this.patientId});
  final ApiClient api;
  final String hospitalId, patientId;
  @override
  State<ConcernSummaryPanel> createState() => _ConcernSummaryPanelState();
}

class _ConcernSummaryPanelState extends State<ConcernSummaryPanel> {
  final _month =
      TextEditingController(text: DateTime.now().toString().substring(0, 7));
  Future<Map<String, dynamic>>? _result;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _result = widget.api.concernSummary(
        widget.hospitalId, widget.patientId, _month.text.trim());
  }

  @override
  void didUpdateWidget(covariant ConcernSummaryPanel old) {
    super.didUpdateWidget(old);
    if (old.patientId != widget.patientId ||
        old.hospitalId != widget.hospitalId) {
      _load();
    }
  }

  @override
  void dispose() {
    _month.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly patient concerns',
                style: Theme.of(context).textTheme.titleLarge),
            const Text(
                'Only reports explicitly shared by this patient. Report counts are not diagnoses.'),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _month,
                      decoration:
                          const InputDecoration(labelText: 'Month (YYYY-MM)'))),
              IconButton(
                  tooltip: 'Load concern summary',
                  onPressed: () => setState(_load),
                  icon: const Icon(Icons.refresh))
            ]),
            FutureBuilder<Map<String, dynamic>>(
                future: _result,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                        'Concern summary unavailable: ${snapshot.error}');
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final summary = snapshot.data!['summary'] as Map;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                            '${summary['report_count']} shared reports · ${summary['urgent_report_count']} urgent flags'),
                        for (final item
                            in (summary['patterns'] as List).whereType<Map>())
                          ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                  '${item['name']} · ${item['count']} reports'),
                              subtitle: Text(
                                  'Reported severity: ${item['reported_severity_change']}'),
                              children: [
                                for (final occurrence
                                    in (item['occurrences'] as List)
                                        .whereType<Map>())
                                  ListTile(
                                      title: Text(
                                          '${occurrence['reported_at']} · ${occurrence['severity']}'),
                                      subtitle: Text(
                                          '${occurrence['onset']} · ${occurrence['frequency']}\n${occurrence['details']}'))
                              ]),
                        for (final insight
                            in (summary['ai_insights'] as List? ?? [])
                                .whereType<Map>())
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                  'AI draft: ${insight['text']}\nSources: ${(insight['source_report_ids'] as List).join(', ')}')),
                      ]);
                })
          ])));
}
