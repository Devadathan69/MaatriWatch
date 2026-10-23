import 'package:flutter/material.dart';
import '../../core/patient_api.dart';
import '../../core/video_frame.dart';

class ConsultationsPage extends StatefulWidget {
  const ConsultationsPage({super.key, required this.api});
  final PatientApi api;
  @override
  State<ConsultationsPage> createState() => _ConsultationsPageState();
}

class _ConsultationsPageState extends State<ConsultationsPage> {
  List<Map<String, dynamic>> _slots = [], _visits = [];
  String? _error;
  bool _busy = false, _videoReady = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait(
          [widget.api.consultationSlots(), widget.api.consultations()]);
      if (!mounted) return;
      setState(() {
        _slots = (values[0]['items'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _visits = (values[1]['items'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _videoReady = values[1]['video_configured'] == true;
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
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _when(Map slot) {
    final start = DateTime.parse(slot['start_at'] as String).toLocal();
    final end = DateTime.parse(slot['end_at'] as String).toLocal();
    return '${start.day}/${start.month}/${start.year} · ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}–${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')} (${start.timeZoneName})';
  }

  Future<void> _book(Map slot) async {
    final reason = TextEditingController();
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Book this video visit?'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_when(slot)),
                      Text(slot['clinician_name'] as String? ??
                          'Care team clinician'),
                      const SizedBox(height: 12),
                      TextField(
                          controller: reason,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                              labelText:
                                  'A note for your clinician (optional)')),
                      const Text(
                          'This is a scheduled, non-emergency consultation.')
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Back')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Confirm booking'))
                ]));
    if (yes == true) {
      await _run(() async {
        await widget.api
            .bookConsultation(slot['id'] as String, reason.text.trim());
      });
    }
    Future<void>.delayed(const Duration(seconds: 1), reason.dispose);
  }

  Future<void> _cancel(Map visit) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Cancel this visit?'),
                content: Text(_when(visit)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Keep visit')),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Cancel visit'))
                ]));
    if (yes == true) {
      await _run(() async {
        await widget.api.changeConsultation(visit['id'] as String, 'cancel');
      });
    }
  }

  Future<void> _reschedule(Map visit) async {
    final id = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
                child: ListView(padding: const EdgeInsets.all(20), children: [
              Text('Choose a new time',
                  style: Theme.of(c).textTheme.titleLarge),
              const Text(
                  'Your old reservation is released only if the new booking succeeds.'),
              if (_slots.isEmpty)
                const Text('No replacement slots are available.'),
              for (final slot in _slots)
                ListTile(
                    title: Text(_when(slot)),
                    subtitle: Text(slot['clinician_name'] as String? ??
                        'Care team clinician'),
                    onTap: () => Navigator.pop(c, slot['id'] as String))
            ])));
    if (id != null) {
      await _run(() async {
        await widget.api.changeConsultation(visit['id'] as String, 'reschedule',
            slotId: id);
      });
    }
  }

  Future<void> _join(Map visit) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Join your private video visit'),
                content: const Text(
                    'Video is provided by Daily. Joining shares audio/video and connection metadata with the provider and the clinician. Camera/microphone permission is requested separately. Automatic recording is off.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Not now')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Continue to video'))
                ]));
    if (yes != true) return;
    await _run(() async {
      final result = await widget.api.joinConsultation(visit['id'] as String);
      if (!mounted) return;
      final join = result['join'] as Map;
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Your consultation')),
              body: VideoCallFrame(
                  url: join['room_url'] as String,
                  token: join['token'] as String))));
    });
  }

  bool _canJoin(Map row) {
    final now = DateTime.now().toUtc();
    return row['status'] == 'booked' &&
        now.isAfter(DateTime.parse(row['start_at'] as String)
            .subtract(const Duration(minutes: 10))) &&
        now.isBefore(DateTime.parse(row['end_at'] as String));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xffFFF9F4),
      appBar: AppBar(title: const Text('Your care, face to face'), actions: [
        IconButton(
            tooltip: 'Refresh visits',
            onPressed: _load,
            icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: const Color(0xffE7EDE3),
                borderRadius: BorderRadius.circular(26)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.video_camera_front_outlined,
                  size: 36, color: Color(0xff617E65)),
              const SizedBox(height: 12),
              Text('Make a little time\nfor your care.',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Choose a time with your hospital care team. For urgent symptoms, seek emergency care instead of waiting for an appointment.')
            ])),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (!_videoReady)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                  'Booking is available. Video calling needs the hospital’s Daily configuration before a call can connect.')),
        const SizedBox(height: 20),
        Text('Your visits', style: Theme.of(context).textTheme.titleLarge),
        if (_visits.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No visits booked yet.')),
        for (final visit in _visits)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_when(visit),
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            '${visit['clinician_name'] ?? 'Care team clinician'} · ${visit['status']}'),
                        if (visit['status'] == 'booked') ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 10, children: [
                            FilledButton.icon(
                                onPressed:
                                    _busy || !_videoReady || !_canJoin(visit)
                                        ? null
                                        : () => _join(visit),
                                icon: const Icon(Icons.videocam_outlined),
                                label: const Text('Join video')),
                            TextButton(
                                onPressed:
                                    _busy ? null : () => _reschedule(visit),
                                child: const Text('Reschedule')),
                            TextButton(
                                onPressed: _busy ? null : () => _cancel(visit),
                                child: const Text('Cancel'))
                          ]),
                          const Text(
                              'Video opens ten minutes before the scheduled start.',
                              style: TextStyle(fontSize: 12)),
                        ]
                      ]))),
        const SizedBox(height: 24),
        Text('Available times', style: Theme.of(context).textTheme.titleLarge),
        const Text('Times are shown in your device timezone.'),
        if (_slots.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Your clinicians have not published any available slots. You can ask your care team for a suitable time.')),
        for (final slot in _slots)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(_when(slot)),
                  subtitle: Text(slot['clinician_name'] as String? ??
                      'Care team clinician'),
                  trailing: TextButton(
                      onPressed: _busy ? null : () => _book(slot),
                      child: const Text('Book')))),
      ]));
}
