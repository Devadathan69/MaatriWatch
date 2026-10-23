import 'package:flutter/material.dart';
import 'package:maatriwatch_patient_app/core/video_frame.dart';
import '../../core/api_client.dart';
import '../../widgets/concern_summary_panel.dart';

class ClinicianConsultationsPage extends StatefulWidget {
  const ClinicianConsultationsPage(
      {super.key, required this.api, required this.hospitalId});
  final ApiClient api;
  final String hospitalId;
  @override
  State<ClinicianConsultationsPage> createState() =>
      _ClinicianConsultationsPageState();
}

class _ClinicianConsultationsPageState
    extends State<ClinicianConsultationsPage> {
  List<Map<String, dynamic>> _slots = [], _visits = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Future.wait([
        widget.api.consultationSlots(widget.hospitalId),
        widget.api.consultations(widget.hospitalId)
      ]);
      if (mounted) {
        setState(() {
          _slots = (result[0]['items'] as List)
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
          _visits = (result[1]['items'] as List)
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
        });
      }
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
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _when(Map row) =>
      '${DateTime.parse(row['start_at'] as String).toLocal()} – ${DateTime.parse(row['end_at'] as String).toLocal()}';
  Future<void> _publish() async {
    final now = DateTime.now();
    final day = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 89)));
    if (day == null || !mounted) return;
    final time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    final start =
        DateTime(day.year, day.month, day.day, time.hour, time.minute).toUtc();
    await _run(() async {
      await widget.api.publishConsultation(
          widget.hospitalId,
          start.toIso8601String(),
          start.add(const Duration(minutes: 30)).toIso8601String());
    });
  }

  Future<void> _join(Map visit) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Open private consultation'),
                content: const Text(
                    'Daily provides the audio/video connection. Joining shares audio/video and connection metadata with the provider and booked patient. Recording/transcription do not start automatically.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Back')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Join'))
                ]));
    if (yes != true) return;
    await _run(() async {
      final data = await widget.api
          .joinConsultation(widget.hospitalId, visit['id'] as String);
      if (!mounted) return;
      final join = data['join'] as Map;
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Private consultation')),
              body: VideoCallFrame(
                  url: join['room_url'] as String,
                  token: join['token'] as String))));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar:
          AppBar(title: const Text('Video consultation schedule'), actions: [
        IconButton(
            tooltip: 'Refresh schedule',
            onPressed: _load,
            icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
            'Publish your own availability. Booking times are shown in this device’s timezone. Only your booked consultations are shown below.'),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _busy ? null : _publish,
            icon: const Icon(Icons.add),
            label: const Text('Publish a 30-minute slot')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 20),
        Text('Booked consultations',
            style: Theme.of(context).textTheme.titleLarge),
        if (_visits.isEmpty) const Text('No booked visits.'),
        for (final visit in _visits)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${visit['patient_name']} · ${visit['status']}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(_when(visit)),
                        Text(visit['reason'] as String? ?? ''),
                        ExpansionTile(
                            title: const Text('Review shared concern summary'),
                            children: [
                              ConcernSummaryPanel(
                                  api: widget.api,
                                  hospitalId: widget.hospitalId,
                                  patientId: visit['patient_id'] as String)
                            ]),
                        if (visit['status'] == 'booked')
                          Wrap(spacing: 8, children: [
                            FilledButton.icon(
                                onPressed: _busy ? null : () => _join(visit),
                                icon: const Icon(Icons.videocam_outlined),
                                label: const Text('Join video')),
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                          await widget.api.changeConsultation(
                                              widget.hospitalId,
                                              visit['id'] as String,
                                              'complete');
                                        }),
                                child: const Text('Mark complete')),
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                          await widget.api.changeConsultation(
                                              widget.hospitalId,
                                              visit['id'] as String,
                                              'cancel');
                                        }),
                                child: const Text('Cancel visit'))
                          ])
                      ]))),
        const SizedBox(height: 20),
        Text('Open availability',
            style: Theme.of(context).textTheme.titleLarge),
        for (final slot in _slots)
          Card(
              child: ListTile(
                  title: Text(_when(slot)),
                  subtitle:
                      Text(slot['clinician_name'] as String? ?? 'Clinician'),
                  trailing: IconButton(
                      tooltip: 'Close this slot',
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await widget.api.closeConsultationSlot(
                                    widget.hospitalId, slot['id'] as String);
                              }),
                      icon: const Icon(Icons.close)))),
      ]));
}
