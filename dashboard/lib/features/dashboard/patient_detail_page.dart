import 'package:flutter/material.dart';
import '../../widgets/concern_summary_panel.dart';
import '../../widgets/nutrition_review_panel.dart';
import 'package:intl/intl.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/vital_trend_chart.dart';

class PatientDetailPage extends StatefulWidget {
  const PatientDetailPage({
    super.key,
    required this.api,
    required this.hospital,
    required this.patient,
  });

  final ApiClient api;
  final HospitalMembership hospital;
  final PatientSummary patient;

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  PatientDetail? _detail;
  List<VitalReading> _vitals = const [];
  List<ClinicalNote> _notes = const [];
  List<AlertItem> _alerts = const [];
  List<CareMessage> _messages = const [];
  bool _loading = true;
  bool _savingNote = false;
  bool _sendingMessage = false;
  bool _savingGuidance = false;
  String? _error;
  VitalMetric _metric = VitalMetric.heartRate;
  final _note = TextEditingController();
  final _message = TextEditingController();
  final _guidanceTitle = TextEditingController();
  final _guidanceBody = TextEditingController();
  String _guidanceCategory = 'gdm_support';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _message.dispose();
    _guidanceTitle.dispose();
    _guidanceBody.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.api.patient(widget.hospital.hospitalId, widget.patient.id),
        widget.api.vitals(widget.hospital.hospitalId, widget.patient.id),
        widget.api.notes(widget.hospital.hospitalId, widget.patient.id),
        widget.api
            .alerts(widget.hospital.hospitalId, patientId: widget.patient.id),
        widget.api.careMessages(widget.hospital.hospitalId, widget.patient.id),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = values[0] as PatientDetail;
        _vitals = values[1] as List<VitalReading>;
        _notes = values[2] as List<ClinicalNote>;
        _alerts = values[3] as List<AlertItem>;
        _messages = values[4] as List<CareMessage>;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'We could not load this patient record. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _createNote() async {
    final text = _note.text.trim();
    if (text.isEmpty || _savingNote) return;
    setState(() => _savingNote = true);
    try {
      final created = await widget.api
          .createNote(widget.hospital.hospitalId, widget.patient.id, text);
      if (!mounted) return;
      setState(() {
        _notes = [created, ..._notes];
        _note.clear();
      });
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _sendCareMessage() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sendingMessage) return;
    CareMessage? replyTo;
    for (final item in _messages.reversed) {
      if (item.senderRole == 'patient') {
        replyTo = item;
        break;
      }
    }
    setState(() => _sendingMessage = true);
    try {
      final sent = await widget.api.sendCareMessage(
        widget.hospital.hospitalId,
        widget.patient.id,
        text,
        inReplyTo: replyTo?.id,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, sent];
        _message.clear();
      });
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  Future<void> _createGuidance() async {
    final title = _guidanceTitle.text.trim();
    final body = _guidanceBody.text.trim();
    if (title.isEmpty || body.isEmpty || _savingGuidance) return;
    setState(() => _savingGuidance = true);
    try {
      await widget.api.createGuidance(
        widget.hospital.hospitalId,
        widget.patient.id,
        category: _guidanceCategory,
        title: title,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _guidanceTitle.clear();
        _guidanceBody.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Clinician-approved guidance is now available to the patient.')));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _savingGuidance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.patient.name ?? widget.patient.name),
        actions: [
          IconButton(
              tooltip: 'Refresh patient record',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: MaatriTokens.space8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : detail == null
                  ? const SizedBox.shrink()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1000;
                        final main = _mainColumn(context, detail);
                        final side = _notesAndAlerts(context);
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(MaatriTokens.space16),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 3, child: main),
                                    const SizedBox(width: MaatriTokens.space16),
                                    Expanded(flex: 2, child: side),
                                  ],
                                )
                              : Column(children: [
                                  main,
                                  const SizedBox(height: MaatriTokens.space16),
                                  side
                                ]),
                        );
                      },
                    ),
    );
  }

  Widget _mainColumn(BuildContext context, PatientDetail detail) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConcernSummaryPanel(
              api: widget.api,
              hospitalId: widget.hospital.hospitalId,
              patientId: widget.patient.id),
          NutritionReviewPanel(
              api: widget.api,
              hospitalId: widget.hospital.hospitalId,
              patientId: widget.patient.id),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: MaatriTokens.space16,
                runSpacing: MaatriTokens.space12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.patient.name,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: MaatriTokens.space4),
                      Text(
                          'MRN ${detail.patient.medicalRecordNumber}  •  ${detail.patient.language ?? 'Language not recorded'}'),
                      if (detail.patient.deliveryDate != null)
                        Text(
                            'Delivery date: ${DateFormat('d MMM y').format(detail.patient.deliveryDate!)}'),
                    ],
                  ),
                  StatusChip(status: detail.status),
                ],
              ),
            ),
          ),
          const SizedBox(height: MaatriTokens.space16),
          _AssignedWatchCard(device: detail.device),
          const SizedBox(height: MaatriTokens.space16),
          _VitalsSnapshot(reading: detail.latestVital),
          const SizedBox(height: MaatriTokens.space16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: MaatriTokens.space12,
                    runSpacing: MaatriTokens.space8,
                    children: [
                      Text('Vital trends (last 24 hours)',
                          style: Theme.of(context).textTheme.titleLarge),
                      SegmentedButton<VitalMetric>(
                        segments: VitalMetric.values
                            .map((metric) => ButtonSegment(
                                value: metric, label: Text(metric.label)))
                            .toList(growable: false),
                        selected: {_metric},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) =>
                            setState(() => _metric = selection.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: MaatriTokens.space16),
                  VitalTrendChart(items: _vitals, metric: _metric),
                ],
              ),
            ),
          ),
          if (detail.latestScreening != null &&
              detail.latestScreening!.isNotEmpty) ...[
            const SizedBox(height: MaatriTokens.space16),
            _ScreeningSummary(screening: detail.latestScreening!),
          ],
        ],
      );

  Widget _notesAndAlerts(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Clinician-approved guidance',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: MaatriTokens.space8),
                    const Text(
                        'Only use this for advice you have individually reviewed. It is not an automated diet or prescribing tool.'),
                    const SizedBox(height: MaatriTokens.space8),
                    DropdownButtonFormField<String>(
                      initialValue: _guidanceCategory,
                      decoration:
                          const InputDecoration(labelText: 'Guidance area'),
                      items: const [
                        DropdownMenuItem(
                            value: 'gdm_support', child: Text('GDM support')),
                        DropdownMenuItem(
                            value: 'thyroid_followup',
                            child: Text('Thyroid follow-up')),
                        DropdownMenuItem(
                            value: 'activity', child: Text('Activity')),
                        DropdownMenuItem(
                            value: 'wellbeing', child: Text('Wellbeing')),
                      ],
                      onChanged: (value) => setState(
                          () => _guidanceCategory = value ?? 'gdm_support'),
                    ),
                    const SizedBox(height: MaatriTokens.space8),
                    TextField(
                      controller: _guidanceTitle,
                      maxLength: 160,
                      decoration: const InputDecoration(
                          hintText: 'Title for the patient'),
                    ),
                    TextField(
                      controller: _guidanceBody,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 4000,
                      decoration:
                          const InputDecoration(hintText: 'Reviewed guidance'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _savingGuidance ? null : _createGuidance,
                        icon: _savingGuidance
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.verified_outlined),
                        label: const Text('Publish guidance'),
                      ),
                    ),
                  ]),
            ),
          ),
          const SizedBox(height: MaatriTokens.space16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Patient messages (${_messages.length})',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                        tooltip: 'Refresh messages',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: MaatriTokens.space8),
                  const Text(
                      'Asynchronous, non-emergency communication. Do not use for urgent care.'),
                  const SizedBox(height: MaatriTokens.space8),
                  if (widget.api.demoRole != null)
                    const Text(
                        'Live messages require a signed-in hospital account. The isolated demo does not send or receive patient messages.')
                  else if (_messages.isEmpty)
                    const Text('No patient messages yet.')
                  else
                    ..._recentMessages.map((message) => Padding(
                          padding: const EdgeInsets.only(
                              bottom: MaatriTokens.space8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    message.senderRole == 'patient'
                                        ? '${widget.patient.name} • Patient'
                                        : (message.senderName ?? 'Clinician'),
                                    style:
                                        Theme.of(context).textTheme.labelLarge),
                                Text(message.body),
                                if (message.createdAt != null)
                                  Text(
                                      DateFormat('d MMM, HH:mm')
                                          .format(message.createdAt!),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall),
                              ]),
                        )),
                  if (widget.api.demoRole == null) ...[
                    TextField(
                      controller: _message,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                          hintText: 'Reply to the patient'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _sendingMessage ? null : _sendCareMessage,
                        icon: _sendingMessage
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_outlined),
                        label: const Text('Send reply'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: MaatriTokens.space16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Clinical notes',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: MaatriTokens.space12),
                  TextField(
                    controller: _note,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 5000,
                    decoration:
                        const InputDecoration(hintText: 'Add a clinical note'),
                  ),
                  const SizedBox(height: MaatriTokens.space8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _savingNote ? null : _createNote,
                      icon: _savingNote
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_comment_outlined),
                      label: const Text('Add note'),
                    ),
                  ),
                  const Divider(height: MaatriTokens.space32),
                  if (_notes.isEmpty)
                    const Text('No clinical notes yet.')
                  else
                    ..._notes.map(
                      (note) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: MaatriTokens.space16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(note.note),
                            const SizedBox(height: MaatriTokens.space4),
                            Text(
                              '${note.authorName ?? 'Clinician'}${note.createdAt == null ? '' : '  •  ${DateFormat('d MMM, HH:mm').format(note.createdAt!)}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MaatriTokens.space16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(MaatriTokens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active alerts',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: MaatriTokens.space12),
                  if (_alerts.isEmpty)
                    const Text('No active alerts.')
                  else
                    ..._alerts.map(
                      (alert) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: MaatriTokens.space12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(spacing: MaatriTokens.space8, children: [
                              StatusChip(status: alert.severity, compact: true),
                              StatusChip(status: alert.status, compact: true)
                            ]),
                            const SizedBox(height: MaatriTokens.space4),
                            Text(alert.message),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );

  List<CareMessage> get _recentMessages {
    const maxVisible = 12;
    if (_messages.length <= maxVisible) return _messages;
    return _messages.sublist(_messages.length - maxVisible);
  }
}

class _VitalsSnapshot extends StatelessWidget {
  const _VitalsSnapshot({this.reading});

  final VitalReading? reading;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _VitalValue(
          icon: Icons.favorite_outline_rounded,
          label: 'PPG-derived heart rate',
          value: reading?.heartRate == null
              ? 'Not currently available'
              : '${reading!.heartRate!.toStringAsFixed(0)} bpm',
          context: _measurementContext(reading, reading?.heartRateSource)),
      _VitalValue(
          icon: Icons.air_rounded,
          label: 'PPG-derived SpO₂',
          value: reading?.spo2 == null
              ? 'Not currently available'
              : '${reading!.spo2!.toStringAsFixed(0)}%',
          context: _measurementContext(reading, reading?.spo2Source)),
      _VitalValue(
        icon: Icons.thermostat_outlined,
        label: 'Environmental temperature',
        value: reading?.ambientTemperature == null
            ? 'Not currently available'
            : '${reading!.ambientTemperature!.toStringAsFixed(1)} °C${reading!.ambientHumidity == null ? '' : '  ${reading!.ambientHumidity!.toStringAsFixed(0)}%'}',
        context: _measurementContext(reading, 'environmental_sensor'),
      ),
      _VitalValue(
        icon: Icons.device_thermostat_outlined,
        label: 'Device / skin-adjacent temperature',
        value: reading?.skinAdjacentTemperature == null
            ? 'Not currently available'
            : '${reading!.skinAdjacentTemperature!.toStringAsFixed(1)} °C',
        context: _measurementContext(reading, reading?.temperatureSource),
      ),
      _VitalValue(
        icon: Icons.monitor_heart_outlined,
        label: 'Blood pressure (validated source)',
        value: !_validBloodPressure(reading) ||
                reading?.systolic == null ||
                reading?.diastolic == null
            ? 'Not currently available'
            : '${reading!.systolic!.toStringAsFixed(0)}/${reading!.diastolic!.toStringAsFixed(0)}',
        context: _measurementContext(reading, reading?.bloodPressureSource),
      ),
    ];
    return Wrap(
      spacing: MaatriTokens.space12,
      runSpacing: MaatriTokens.space12,
      children: cards
          .map((card) => SizedBox(width: 170, child: card))
          .toList(growable: false),
    );
  }
}

class _AssignedWatchCard extends StatelessWidget {
  const _AssignedWatchCard({required this.device});

  final AssignedDevice? device;

  @override
  Widget build(BuildContext context) {
    if (device == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(MaatriTokens.space16),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.watch_off_outlined),
            title: Text('No MaatriWatch assigned'),
            subtitle: Text('Assign a hospital-issued watch before monitoring.'),
          ),
        ),
      );
    }

    final lastSeen = device!.lastSeenAt == null
        ? 'No telemetry received yet'
        : 'Last seen ${DateFormat('d MMM, HH:mm').format(device!.lastSeenAt!)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MaatriTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.watch_outlined),
              const SizedBox(width: MaatriTokens.space8),
              Text('Assigned MaatriWatch',
                  style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: MaatriTokens.space12),
            Wrap(
              spacing: MaatriTokens.space24,
              runSpacing: MaatriTokens.space12,
              children: [
                _DeviceField(
                    label: 'Watch ID', value: device!.id, selectable: true),
                _DeviceField(
                    label: 'Serial number',
                    value: device!.serialNumber ?? 'Not recorded'),
                _DeviceField(
                    label: 'Firmware',
                    value: device!.firmwareVersion ?? 'Not reported'),
                _DeviceField(label: 'Connection', value: lastSeen),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceField extends StatelessWidget {
  const _DeviceField({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 235,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: MaatriTokens.space4),
          selectable
              ? SelectableText(value,
                  style: Theme.of(context).textTheme.bodyMedium)
              : Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ]),
      );
}

class _VitalValue extends StatelessWidget {
  const _VitalValue(
      {required this.icon,
      required this.label,
      required this.value,
      required this.context});

  final IconData icon;
  final String label;
  final String value;
  final String context;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: MaatriTokens.primary),
              const SizedBox(height: MaatriTokens.space12),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: MaatriTokens.space4),
              Text(this.context,
                  style: Theme.of(context).textTheme.labelSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
}

bool _validBloodPressure(VitalReading? reading) => const {
      'validated_cuff',
      'clinician_entered',
    }.contains(reading?.bloodPressureSource);

String _measurementContext(VitalReading? reading, String? source) {
  final sourceText = source == 'environmental_sensor'
      ? 'Environmental sensor (not body temperature)'
      : measurementSourceLabel(source);
  final observed = reading?.observedAt ?? reading?.capturedAt;
  final time = observed == null
      ? 'observation time unavailable'
      : 'observed ${DateFormat('d MMM, HH:mm').format(observed)}';
  return '$sourceText • $time • ${reading?.observationStatus ?? 'unavailable'}';
}

class _ScreeningSummary extends StatelessWidget {
  const _ScreeningSummary({required this.screening});

  final Map<String, dynamic> screening;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Latest screening',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: MaatriTokens.space8),
              Text(
                  '${screening['screening_type'] ?? 'Screening'}  •  ${screening['risk_level'] ?? 'Not classified'}'),
              if (screening['score'] != null)
                Text('Score: ${screening['score']}'),
            ],
          ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: MaatriTokens.warning, size: 42),
              const SizedBox(height: MaatriTokens.space16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: MaatriTokens.space16),
              OutlinedButton(
                  onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}
