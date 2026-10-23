import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/realtime_service.dart';
import '../../widgets/status_chip.dart';
import 'patient_detail_page.dart';
import 'consultations_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.api,
    required this.memberships,
    required this.onSignOut,
    this.demoMode = false,
  });

  final ApiClient api;
  final List<HospitalMembership> memberships;
  final VoidCallback onSignOut;
  final bool demoMode;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _realtime = RealtimeService();
  late HospitalMembership _hospital;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _vitalsSubscription;
  StreamSubscription<Map<String, Map<String, dynamic>>>? _alertsSubscription;
  Timer? _demoPollingTimer;
  List<PatientSummary> _patients = const [];
  List<AlertItem> _alerts = const [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasLiveUpdates = false;
  String? _error;
  String? _liveStatus;
  int _tab = 0;
  String _sort = 'risk';

  @override
  void initState() {
    super.initState();
    _hospital = widget.memberships.first;
    _load();
  }

  @override
  void dispose() {
    _vitalsSubscription?.cancel();
    _alertsSubscription?.cancel();
    _demoPollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool manual = false}) async {
    if (manual) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait([
        widget.api.patients(_hospital.hospitalId, sort: _sort),
        widget.api.alerts(_hospital.hospitalId),
      ]);
      if (!mounted) return;
      // This is the only place the server's sort order replaces the list.
      setState(() {
        _patients = values[0] as List<PatientSummary>;
        _alerts = values[1] as List<AlertItem>;
        _loading = false;
        _refreshing = false;
        _hasLiveUpdates = false;
      });
      _subscribeToLiveUpdates();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'We could not refresh the dashboard. Check your connection and try again.';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _subscribeToLiveUpdates() {
    _vitalsSubscription?.cancel();
    _alertsSubscription?.cancel();
    _demoPollingTimer?.cancel();
    if (widget.demoMode) {
      _demoPollingTimer = Timer.periodic(
          const Duration(seconds: 2), (_) => _pollDemoLiveState());
      return;
    }
    _vitalsSubscription = _realtime.liveVitals(_hospital.hospitalId).listen(
      _mergeLiveVitals,
      onError: (_) {
        if (mounted) {
          setState(() => _liveStatus =
              'Live updates are unavailable. Showing the last loaded data.');
        }
      },
    );
    _alertsSubscription = _realtime.liveAlerts(_hospital.hospitalId).listen(
      _mergeLiveAlerts,
      onError: (_) {
        if (mounted) {
          setState(() => _liveStatus =
              'Live alerts are unavailable. Use Refresh when connected.');
        }
      },
    );
  }

  Future<void> _pollDemoLiveState() async {
    if (!mounted || _refreshing || _loading) return;
    try {
      final values = await Future.wait([
        widget.api.patients(_hospital.hospitalId, sort: _sort),
        widget.api.alerts(_hospital.hospitalId),
      ]);
      if (!mounted) return;
      final remotePatients = values[0] as List<PatientSummary>;
      final remoteAlerts = values[1] as List<AlertItem>;
      final patientById = {
        for (final patient in remotePatients) patient.id: patient
      };
      final alertById = {for (final alert in remoteAlerts) alert.id: alert};
      final knownPatientIds = _patients.map((patient) => patient.id).toSet();
      final knownAlertIds = _alerts.map((alert) => alert.id).toSet();
      setState(() {
        // The demo polling path follows the same non-jumping invariant as RTDB:
        // update an existing row in place and append only genuinely new records.
        _patients = [
          ..._patients.map((patient) => patientById[patient.id] ?? patient),
          ...remotePatients
              .where((patient) => !knownPatientIds.contains(patient.id)),
        ];
        _alerts = [
          ..._alerts
              .where((alert) => alertById.containsKey(alert.id))
              .map((alert) => alertById[alert.id]!),
          ...remoteAlerts.where((alert) => !knownAlertIds.contains(alert.id)),
        ];
        _hasLiveUpdates = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _liveStatus =
            'Live demo polling paused. Use Refresh when the API is available.');
      }
    }
  }

  void _mergeLiveVitals(Map<String, Map<String, dynamic>> values) {
    if (!mounted || _patients.isEmpty) return;
    var changed = false;
    final next = List<PatientSummary>.from(_patients);
    for (var index = 0; index < next.length; index++) {
      final live = values[next[index].id];
      if (live != null) {
        next[index] = next[index].withLiveVital(live);
        changed = true;
      }
    }
    if (changed) {
      // Preserve index/order so live readings cannot move a row beneath a cursor.
      setState(() {
        _patients = next;
        _hasLiveUpdates = true;
        _liveStatus = null;
      });
    }
  }

  void _mergeLiveAlerts(Map<String, Map<String, dynamic>> values) {
    if (!mounted || _alerts.isEmpty && values.isEmpty) return;
    final byId = <String, AlertItem>{for (final item in _alerts) item.id: item};
    var changed = false;
    for (final entry in values.entries) {
      final source = entry.value;
      if (source.isEmpty || source['id'] == null) continue;
      final incoming = AlertItem.fromJson(source);
      final existing = byId[incoming.id];
      if (incoming.status == 'resolved') {
        changed = byId.remove(incoming.id) != null || changed;
        continue;
      }
      final patientName =
          existing?.patientName ?? _patientName(incoming.patientId);
      byId[incoming.id] = AlertItem(
        id: incoming.id,
        patientId: incoming.patientId,
        severity: incoming.severity,
        status: incoming.status,
        type: incoming.type,
        message: incoming.message,
        occurrenceCount: incoming.occurrenceCount,
        patientName: patientName,
        triggeredAt: incoming.triggeredAt,
        lastSeenAt: incoming.lastSeenAt,
        updatedAt: incoming.updatedAt,
      );
      changed = true;
    }
    if (changed) {
      // Retain existing queue order. New live alerts append rather than stealing focus.
      final existingIds = _alerts.map((item) => item.id).toSet();
      final ordered = <AlertItem>[
        ..._alerts
            .where((item) => byId.containsKey(item.id))
            .map((item) => byId[item.id]!),
        ...byId.entries
            .where((entry) => !existingIds.contains(entry.key))
            .map((entry) => entry.value),
      ];
      setState(() {
        _alerts = ordered;
        _hasLiveUpdates = true;
        _liveStatus = null;
      });
    }
  }

  String? _patientName(String patientId) {
    for (final patient in _patients) {
      if (patient.id == patientId) return patient.name;
    }
    return null;
  }

  Future<void> _switchHospital(HospitalMembership value) async {
    if (value.hospitalId == _hospital.hospitalId) return;
    await _vitalsSubscription?.cancel();
    await _alertsSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _hospital = value;
      _patients = const [];
      _alerts = const [];
      _hasLiveUpdates = false;
      _liveStatus = null;
    });
    await _load();
  }

  Future<void> _changeSort(String sort) async {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    await _load(manual: true);
  }

  Future<void> _handleAlertAction(AlertItem alert, String action) async {
    String? note;
    if (action == 'resolve' || action == 'escalate') {
      note = await _askForNote(action);
      if (note == null) return;
    }
    try {
      final updated = await widget.api.updateAlert(
        _hospital.hospitalId,
        alert.id,
        action: action,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        if (updated.status == 'resolved') {
          _alerts = _alerts
              .where((item) => item.id != updated.id)
              .toList(growable: false);
        } else {
          _alerts = _alerts
              .map((item) => item.id == updated.id
                  ? AlertItem(
                      id: updated.id,
                      patientId: updated.patientId,
                      severity: updated.severity,
                      status: updated.status,
                      type: updated.type,
                      message: updated.message,
                      occurrenceCount: updated.occurrenceCount,
                      patientName: item.patientName,
                      triggeredAt: updated.triggeredAt,
                      lastSeenAt: updated.lastSeenAt,
                      updatedAt: updated.updatedAt,
                    )
                  : item)
              .toList(growable: false);
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Alert ${action}d.')));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<String?> _askForNote(String action) async {
    final controller = TextEditingController();
    final label = action == 'resolve' ? 'Resolution note' : 'Escalation note';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 5000,
          decoration: const InputDecoration(
              hintText: 'Briefly record the clinical handoff or outcome.'),
        ),
        actions: [
          IconButton(
              tooltip: 'Video consultation schedule',
              icon: const Icon(Icons.video_camera_front_outlined),
              onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                      builder: (_) => ClinicianConsultationsPage(
                          api: widget.api, hospitalId: _hospital.hospitalId)))),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child:
                Text(action == 'resolve' ? 'Resolve alert' : 'Escalate alert'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A clinical note is required.')));
      }
      return null;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = [
      _PatientsPane(
        loading: _loading,
        refreshing: _refreshing,
        patients: _patients,
        sort: _sort,
        hasLiveUpdates: _hasLiveUpdates,
        onSortChanged: _changeSort,
        onRefresh: () => _load(manual: true),
        onPatientSelected: (patient) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PatientDetailPage(
                api: widget.api, hospital: _hospital, patient: patient),
          ),
        ),
      ),
      _AlertQueuePane(
        loading: _loading,
        refreshing: _refreshing,
        alerts: _alerts,
        onRefresh: () => _load(manual: true),
        onAction: _handleAlertAction,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: MaatriTokens.space16,
        title: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: MaatriTokens.primary),
            const SizedBox(width: MaatriTokens.space8),
            const Text('MaatriWatch'),
            const SizedBox(width: MaatriTokens.space12),
            Flexible(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<HospitalMembership>(
                  value: _hospital,
                  isDense: true,
                  icon: const Icon(Icons.expand_more_rounded),
                  items: widget.memberships
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.hospitalName,
                              overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) _switchHospital(value);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: MaatriTokens.space8),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            _DashboardBanner(message: _error!, critical: false),
          if (_liveStatus != null)
            _DashboardBanner(message: _liveStatus!, critical: false),
          Expanded(
            child: Row(
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: _tab,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (index) =>
                        setState(() => _tab = index),
                    destinations: const [
                      NavigationRailDestination(
                          icon: Icon(Icons.people_outline),
                          selectedIcon: Icon(Icons.people),
                          label: Text('Patients')),
                      NavigationRailDestination(
                          icon: Icon(Icons.notifications_none),
                          selectedIcon: Icon(Icons.notifications),
                          label: Text('Alerts')),
                    ],
                  ),
                Expanded(child: pages[_tab]),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people),
                    label: 'Patients'),
                NavigationDestination(
                    icon: Icon(Icons.notifications_none),
                    selectedIcon: Icon(Icons.notifications),
                    label: 'Alerts'),
              ],
            ),
    );
  }
}

class _PatientsPane extends StatelessWidget {
  const _PatientsPane({
    required this.loading,
    required this.refreshing,
    required this.patients,
    required this.sort,
    required this.hasLiveUpdates,
    required this.onSortChanged,
    required this.onRefresh,
    required this.onPatientSelected,
  });

  final bool loading;
  final bool refreshing;
  final List<PatientSummary> patients;
  final String sort;
  final bool hasLiveUpdates;
  final ValueChanged<String> onSortChanged;
  final Future<void> Function() onRefresh;
  final ValueChanged<PatientSummary> onPatientSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(MaatriTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: MaatriTokens.space12,
              runSpacing: MaatriTokens.space8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patients',
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text('${patients.length} assigned to this hospital',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      value: sort,
                      items: const [
                        DropdownMenuItem(
                            value: 'risk', child: Text('Sort: risk')),
                        DropdownMenuItem(
                            value: 'recent', child: Text('Sort: recent')),
                        DropdownMenuItem(
                            value: 'name', child: Text('Sort: name')),
                      ],
                      onChanged: (value) {
                        if (value != null) onSortChanged(value);
                      },
                    ),
                    const SizedBox(width: MaatriTokens.space8),
                    IconButton(
                      tooltip: 'Refresh list',
                      onPressed: refreshing ? null : onRefresh,
                      icon: refreshing
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ],
            ),
            if (hasLiveUpdates) ...[
              const SizedBox(height: MaatriTokens.space12),
              const _LiveUpdateNotice(),
            ],
            const SizedBox(height: MaatriTokens.space16),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : patients.isEmpty
                      ? const _EmptyPanel(
                          icon: Icons.people_outline,
                          message:
                              'No active patients are available in this hospital.')
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            itemCount: patients.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) => _PatientRow(
                              key: ValueKey(patients[index].id),
                              patient: patients[index],
                              onTap: () => onPatientSelected(patients[index]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      );
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({super.key, required this.patient, required this.onTap});

  final PatientSummary patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final heartRate = patient.latestVital?.heartRate;
    final time = patient.latestVital?.capturedAt;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: MaatriTokens.space16, vertical: MaatriTokens.space8),
      leading: CircleAvatar(
        backgroundColor:
            MaatriTokens.statusColor(patient.status).withValues(alpha: 0.12),
        foregroundColor: MaatriTokens.statusColor(patient.status),
        child: const Icon(Icons.person_outline_rounded),
      ),
      title: Text(patient.name, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(
        '${patient.medicalRecordNumber}  •  ${heartRate == null ? 'No recent heart-rate reading' : '${heartRate.toStringAsFixed(0)} bpm'}'
        '${time == null ? '' : '  •  ${DateFormat('HH:mm').format(time)}'}',
      ),
      trailing: SizedBox(
        width: 142,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (patient.activeAlertCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: MaatriTokens.space8),
                child: Semantics(
                    label: '${patient.activeAlertCount} active alerts',
                    child: Text('${patient.activeAlertCount}')),
              ),
            StatusChip(status: patient.status, compact: true),
          ],
        ),
      ),
      onTap: onTap,
    );
  }
}

class _AlertQueuePane extends StatelessWidget {
  const _AlertQueuePane({
    required this.loading,
    required this.refreshing,
    required this.alerts,
    required this.onRefresh,
    required this.onAction,
  });

  final bool loading;
  final bool refreshing;
  final List<AlertItem> alerts;
  final Future<void> Function() onRefresh;
  final Future<void> Function(AlertItem, String) onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(MaatriTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('Alert queue',
                        style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                  tooltip: 'Refresh alerts',
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: MaatriTokens.space16),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : alerts.isEmpty
                      ? const _EmptyPanel(
                          icon: Icons.notifications_off_outlined,
                          message: 'No active alerts. Continue routine review.')
                      : ListView.separated(
                          itemCount: alerts.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: MaatriTokens.space12),
                          itemBuilder: (context, index) => _AlertCard(
                              alert: alerts[index], onAction: onAction),
                        ),
            ),
          ],
        ),
      );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onAction});

  final AlertItem alert;
  final Future<void> Function(AlertItem, String) onAction;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: MaatriTokens.space8,
                  runSpacing: MaatriTokens.space8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(status: alert.severity),
                    StatusChip(status: alert.status),
                    Text(alert.patientName ?? 'Patient record',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: MaatriTokens.space12),
                Text(alert.type,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: MaatriTokens.space4),
                Text(alert.message),
                const SizedBox(height: MaatriTokens.space8),
                Text(
                  '${alert.occurrenceCount} occurrence${alert.occurrenceCount == 1 ? '' : 's'}'
                  '${alert.lastSeenAt == null ? '' : '  •  last seen ${DateFormat('d MMM, HH:mm').format(alert.lastSeenAt!)}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: MaatriTokens.space16),
                Wrap(
                  spacing: MaatriTokens.space8,
                  runSpacing: MaatriTokens.space8,
                  children: [
                    if (alert.status == 'open')
                      OutlinedButton.icon(
                        onPressed: () => onAction(alert, 'acknowledge'),
                        icon: const Icon(Icons.visibility_rounded),
                        label: const Text('Acknowledge'),
                      ),
                    if (alert.status != 'escalated')
                      OutlinedButton.icon(
                        onPressed: () => onAction(alert, 'escalate'),
                        icon: const Icon(Icons.north_east_rounded),
                        label: const Text('Escalate'),
                      ),
                    ElevatedButton.icon(
                      onPressed: () => onAction(alert, 'resolve'),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Resolve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _DashboardBanner extends StatelessWidget {
  const _DashboardBanner({required this.message, required this.critical});

  final String message;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final color = critical ? MaatriTokens.critical : MaatriTokens.warning;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.all(MaatriTokens.space12),
      child: Row(
        children: [
          Icon(critical ? Icons.warning_rounded : Icons.cloud_off_outlined,
              color: color),
          const SizedBox(width: MaatriTokens.space8),
          Expanded(
              child: Text(message,
                  style: MaatriTokens.type(
                      size: MaatriTokens.type14, color: color))),
        ],
      ),
    );
  }
}

class _LiveUpdateNotice extends StatelessWidget {
  const _LiveUpdateNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(MaatriTokens.space12),
        decoration: BoxDecoration(
          color: MaatriTokens.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(MaatriTokens.radius8),
        ),
        child: Row(
          children: [
            const Icon(Icons.sync_rounded, color: MaatriTokens.primary),
            const SizedBox(width: MaatriTokens.space8),
            Expanded(
              child: Text(
                'Live readings updated. Your current list order has been kept unchanged.',
                style: MaatriTokens.type(
                    size: MaatriTokens.type14, color: MaatriTokens.primaryDark),
              ),
            ),
          ],
        ),
      );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: MaatriTokens.surfaceMuted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(MaatriTokens.radius12),
          border: Border.all(
              color: MaatriTokens.border, style: BorderStyle.solid, width: 1.5),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(MaatriTokens.space24),
                  decoration: BoxDecoration(
                    color: MaatriTokens.canvas,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10)
                    ],
                  ),
                  child: Icon(icon,
                      size: 48,
                      color: MaatriTokens.primary.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: MaatriTokens.space24),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: MaatriTokens.type(
                      size: MaatriTokens.type16,
                      color: MaatriTokens.textMuted,
                      weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
}
