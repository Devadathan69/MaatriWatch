import 'package:flutter/material.dart';
import '../../core/patient_api.dart';

String reminderDate(BuildContext context, dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final local = MaterialLocalizations.of(context);
  return '${local.formatMediumDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';
}

const reminderLeads = {
  0: 'At the event',
  60: '1 hour before',
  1440: '1 day before',
  4320: '3 days before',
  10080: '1 week before',
};

String reminderDescription(BuildContext context, Map data) {
  final status = switch (data['status']) {
    'active' => 'Upcoming', 'completed' => 'Completed', 'cancelled' => 'Cancelled', _ => ''
  };
  final lead = data['snoozed'] == true ? 'Snoozed' : reminderLeads[data['lead_minutes']];
  return '${data['event_at'] != null ? 'Event: ${reminderDate(context,data['event_at'])}\n' : ''}'
      'Remind: ${reminderDate(context,data['due_at'])}\n${lead == null ? '' : '$lead · '}$status';
}

class EventReminderSheet extends StatefulWidget {
  const EventReminderSheet({super.key, required this.api});
  final PatientApi api;
  @override
  State<EventReminderSheet> createState() => _EventReminderSheetState();
}

class _EventReminderSheetState extends State<EventReminderSheet> {
  final _title = TextEditingController();
  DateTime? _event;
  int _lead = 0;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _chooseEvent() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _event ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
      helpText: 'When is your event?',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _event == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(_event!),
    );
    if (time != null && mounted) {
      setState(() {
        _event = DateTime(day.year, day.month, day.day, time.hour, time.minute);
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _event == null) {
      setState(() => _error = 'Add the event name, date and time.');
      return;
    }
    if (!_event!.subtract(Duration(minutes: _lead)).isAfter(DateTime.now())) {
      setState(
        () => _error =
            'That reminder time has already passed. Choose a later event or a shorter notice.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.createReminder({
        'title': _title.text.trim(),
        'event_at': _event!.toUtc().toIso8601String(),
        'lead_minutes': _lead,
        'recurrence': 'none',
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Remember an upcoming event',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'What is the event?',
                hintText: 'Doctor visit, scan, blood test…',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseEvent,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _event == null
                    ? 'Choose event date & time'
                    : reminderDate(context, _event!.toIso8601String()),
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<int>(
              initialValue: _lead,
              decoration: const InputDecoration(
                labelText: 'When should we remind you?',
              ),
              items: [
                for (final e in reminderLeads.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _lead = v!),
            ),
            if (_event != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Reminder: ${reminderDate(context, _event!.subtract(Duration(minutes: _lead)).toIso8601String())}',
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save reminder'),
            ),
          ],
        ),
      ),
    ),
  );
}
