import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/patient_api.dart';
import '../../core/patient_realtime.dart';
import 'patient_followup.dart';
import 'patient_health_actions.dart';
import 'companion_page.dart';
import 'concerns_page.dart';

/// Patient-facing safety companion. It routes concerns to care teams; it does not diagnose.
class PatientHome extends StatefulWidget {
  const PatientHome({
    super.key,
    this.api,
    this.onSignOut,
    this.onAccessDenied,
    this.liveVitals,
  });
  final PatientApi? api;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onAccessDenied;
  final PatientLiveVitalsSource? liveVitals;
  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  PatientApi? _fallbackApi;
  Map<String, dynamic> _data = const {};
  Map<String, bool> _consents = {};
  int _page = 0;
  bool _busy = false;
  bool _labPromptShown = false;
  String? _offline;
  String? _accessDenied;
  String? _liveVitalsMessage;
  Map<String, dynamic>? _firebaseVital;
  StreamSubscription<Map<String, dynamic>?>? _liveVitalsSubscription;
  String? _liveVitalsPath;
  PatientApi get _api => widget.api ?? (_fallbackApi ??= PatientApi());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _liveVitalsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _offline = null;
      _accessDenied = null;
    });
    try {
      final values = await Future.wait([_api.home(), _api.consents()]);
      final consents = values[1]['items'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _data = values[0];
          _consents = {
            for (final item in consents.whereType<Map>())
              item['consent_type'] as String: item['granted'] == true
          };
        });
        _listenForLiveVitals(values[0]);
        if (_data['lab_onboarding_pending'] == true && !_labPromptShown) {
          _labPromptShown = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _showLabOnboarding());
        }
      }
    } on PatientApiException catch (error) {
      if (mounted) {
        if (error.statusCode == 401 || error.statusCode == 403) {
          setState(() => _accessDenied = error.message);
        } else {
          setState(() => _offline =
              'Live data is unavailable. Check your connection before relying on this screen.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _offline =
            'Live data is unavailable. Check your connection before relying on this screen.');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  void _listenForLiveVitals(Map<String, dynamic> home) {
    final source = widget.liveVitals;
    final patient = _map(home['patient']);
    final hospitalId = patient['hospital_id'];
    final patientId = patient['id'];
    if (source == null || hospitalId is! String || patientId is! String) return;

    final path = '$hospitalId/$patientId';
    if (_liveVitalsPath == path) return;
    _liveVitalsPath = path;
    _liveVitalsSubscription?.cancel();
    _liveVitalsSubscription = source
        .latestForPatient(hospitalId: hospitalId, patientId: patientId)
        .listen(
      (vital) {
        if (!mounted) return;
        setState(() {
          _firebaseVital = vital;
          _liveVitalsMessage =
              vital == null ? 'Waiting for a current watch reading.' : null;
        });
      },
      onError: (_) {
        if (mounted) {
          setState(() => _liveVitalsMessage =
              'Live watch updates are unavailable. Showing the last saved reading.');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accessDenied != null) {
      return _AccountAccessDenied(
        message: _accessDenied!,
        onSignOut: widget.onAccessDenied ?? widget.onSignOut,
      );
    }
    return Scaffold(
      body: SafeArea(
          child: RefreshIndicator(
              onRefresh: _load,
              child: IndexedStack(
                  index: _page,
                  children: [_home(), _plan(), _help(), _profile()]))),
      bottomNavigationBar: NavigationBar(
          selectedIndex: _page,
          onDestinationSelected: (i) => setState(() => _page = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Care plan'),
            NavigationDestination(
                icon: Icon(Icons.health_and_safety_outlined),
                selectedIcon: Icon(Icons.health_and_safety),
                label: 'Get help'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile'),
          ]),
    );
  }

  Widget _home() {
    final patient = _map(_data['patient']);
    // Firebase carries the newest live device snapshot. The authenticated API
    // response remains the fallback when Firebase has no node or is offline.
    final vital = _firebaseVital ?? _map(_data['latest_vital']);
    final device = _map(_data['device']);
    final deviceHealth = _map(_data['device_health']);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hello, ${_first(patient['full_name'])}',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(_days(patient['delivery_date']),
              style: Theme.of(context).textTheme.bodyMedium)
        ])),
        IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh')
      ]),
      if (_busy)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator()),
      if (_offline != null)
        _Notice(
            icon: Icons.cloud_off_outlined,
            text: _offline!,
            color: MaatriTokens.warning),
      if (_liveVitalsMessage != null)
        _Notice(
            icon: Icons.watch_later_outlined,
            text: _liveVitalsMessage!,
            color: MaatriTokens.warning),
      const SizedBox(height: 16),
      _Safety(onTap: () => setState(() => _page = 2)),
      const SizedBox(height: 12),
      Card(
          child: ListTile(
        leading: const Icon(Icons.spa_outlined),
        title: const Text('Your MaatriCare companion'),
        subtitle:
            const Text('A place to talk, remember, and take one small step.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openAssistant,
      )),
      const SizedBox(height: 12),
      _alertStatus(),
      const SizedBox(height: 20),
      Text('Your wearable', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const CircleAvatar(
                    backgroundColor: Color(0xffE5F4EF),
                    child: Icon(Icons.watch_outlined,
                        color: MaatriTokens.primary)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          deviceHealth['title'] as String? ??
                              (device.isEmpty
                                  ? 'Wearable not connected'
                                  : 'Wearable connected'),
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                          deviceHealth['message'] as String? ??
                              (vital.isEmpty
                                  ? 'Waiting for a reading'
                                  : _readingContext(vital, 'wearable')),
                          style: Theme.of(context).textTheme.bodySmall),
                      if (vital['activity_context'] != null &&
                          vital['activity_context'] != 'unknown')
                        Text(
                          'Activity context: ${vital['activity_context']}. Readings are still assessed with clinical context.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                    ])),
                if (vital['battery_percent'] != null)
                  Text('${vital['battery_percent']}%',
                      style: const TextStyle(fontWeight: FontWeight.w800))
              ]))),
      const SizedBox(height: 20),
      Text('Latest readings', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Vital(
            'PPG-derived heart rate',
            _reading(vital, 'heart_rate_bpm', 'bpm'),
            _readingContext(vital, _source(vital['heart_rate_source'])),
            Icons.favorite_outline,
            const Color(0xffC9546C)),
        _Vital(
            'PPG-derived SpO₂',
            _reading(vital, 'spo2_percent', '%'),
            _readingContext(vital, _source(vital['spo2_source'])),
            Icons.air_rounded,
            const Color(0xff317D9D)),
        _Vital(
            'Device / skin-adjacent temperature',
            _reading(vital, 'skin_adjacent_temperature_c', '°C'),
            _readingContext(vital, _source(vital['temperature_source'])),
            Icons.thermostat_outlined,
            const Color(0xffD8863F)),
        _Vital(
            'Blood pressure (validated source)',
            _hasValidatedBloodPressure(vital) && _fresh(vital)
                ? '${vital['systolic_bp']}/${vital['diastolic_bp']} mmHg'
                : 'Not currently available',
            _readingContext(vital, _source(vital['blood_pressure_source'])),
            Icons.monitor_heart_outlined,
            const Color(0xff7062A6))
      ]),
      const SizedBox(height: 20),
      _labStatus(),
      const SizedBox(height: 12),
      _guidanceStatus(),
      const SizedBox(height: 20),
      Text('Next step', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      _task((_data['care_plan'] as List? ?? const []).isEmpty
          ? null
          : (_data['care_plan'] as List).first),
      const SizedBox(height: 16),
      Text(
          'Wearable readings support your care team. They do not diagnose illness or replace medical advice.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _plan() {
    final tasks = _data['care_plan'] as List<dynamic>? ?? const [];
    final wellbeing = _map(_data['wellbeing']);
    final completedCheckins = wellbeing['completed_this_week'] ?? 0;
    final recommendedCheckins = wellbeing['recommended_checkins_per_week'] ?? 2;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Your care plan', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text('Small steps help your care team support you between visits.'),
      const SizedBox(height: 16),
      if (tasks.isEmpty)
        const _Empty(
            icon: Icons.event_available_outlined,
            title: 'You are up to date',
            text: 'No care-plan tasks are due.'),
      ...tasks.whereType<Map>().map((t) => _task(t)),
      const SizedBox(height: 12),
      _healthAction(
          icon: Icons.biotech_outlined,
          title: 'Lab result follow-up',
          detail:
              'Paste confirmed glucose or thyroid values for clinician review.',
          action: 'Add a result',
          onPressed: _openLabResults),
      const SizedBox(height: 10),
      _healthAction(
          icon: Icons.self_improvement_outlined,
          title: 'Twice-weekly wellbeing check-in',
          detail:
              '$completedCheckins of $recommendedCheckins check-ins this week. A five-question support check-in, not a diagnosis.',
          action: 'Start check-in',
          onPressed: _openWellbeing),
      const SizedBox(height: 10),
      _activityStatus(),
      const SizedBox(height: 10),
      OutlinedButton.icon(
          onPressed: _openMessages,
          icon: const Icon(Icons.forum_outlined),
          label: Text(
              (_map(_data['messages'])['unread_from_care_team'] as int? ?? 0) >
                      0
                  ? 'Ask your care team • new reply'
                  : 'Ask your care team')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
          onPressed: _report,
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('Complete a wellbeing check-in'))
    ]);
  }

  Widget _help() {
    final signs = _data['danger_signs'] as List<dynamic>? ?? const [];
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Get help', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text(
          'If something does not feel right, trust yourself and ask for help.'),
      const SizedBox(height: 18),
      SizedBox(
          height: 68,
          child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: MaatriTokens.critical,
                  foregroundColor: Colors.white),
              onPressed: _sos,
              icon: const Icon(Icons.sos_rounded, size: 30),
              label: const Text('SOS — I need urgent help'))),
      const SizedBox(height: 10),
      OutlinedButton.icon(
          onPressed: _report,
          icon: const Icon(Icons.edit_note_outlined),
          label: const Text('Report symptoms to my care team')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => ConcernsPage(api: _api))),
          icon: const Icon(Icons.mic_none_rounded),
          label: const Text('Speak Your Concern • English / മലയാളം')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
          onPressed: _openAssistant,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Ask MaatriCare AI')),
      const SizedBox(height: 24),
      Text('Urgent warning signs',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Get emergency care immediately for any of these.'),
      ...signs.whereType<Map>().map((s) => Card(
          child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded,
                  color: MaatriTokens.critical),
              title: Text(s['title'] as String? ?? ''),
              subtitle: Text(s['action'] as String? ?? '')))),
      const _Notice(
          icon: Icons.info_outline,
          text:
              'In an emergency, call your local emergency number or go to the nearest hospital. Do not wait for an app reply.',
          color: MaatriTokens.critical)
    ]);
  }

  Widget _profile() {
    final p = _map(_data['patient']);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Privacy & profile',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(p['hospital_name'] as String? ?? 'Your care team'),
      const SizedBox(height: 18),
      _row(Icons.language_outlined, 'Language',
          p['preferred_language'] as String? ?? 'English'),
      _row(
          Icons.contact_phone_outlined,
          'Emergency contact',
          p['emergency_contact_name'] as String? ??
              'Set up with your care team'),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: _openClinicalProfile,
          icon: const Icon(Icons.medical_information_outlined),
          label: const Text('Update health history for review')),
      const SizedBox(height: 18),
      Text('Sharing choices', style: Theme.of(context).textTheme.titleLarge),
      const Text('Optional sharing can be changed at any time.'),
      _consent('Wearable monitoring', 'Share readings with your care team',
          'monitoring', true),
      _consent('Care-team sharing', 'Share records with assigned clinicians',
          'care_team_sharing', false),
      _consent(
          'Emergency contact',
          'Contact your chosen person when you request help',
          'emergency_contact',
          false),
      _consent('Location during SOS', 'Share location only with an SOS request',
          'location', false),
      const SizedBox(height: 12),
      if (widget.onSignOut != null)
        OutlinedButton.icon(
            onPressed: () async => widget.onSignOut!(),
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Sign out')),
      if (widget.onSignOut != null) const SizedBox(height: 8),
      OutlinedButton.icon(
          onPressed: () => _message(
              'Your care team can help with a record copy or correction request.'),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Request my data'))
    ]);
  }

  Widget _task(dynamic raw) {
    if (raw is! Map) {
      return const _Empty(
          icon: Icons.check_circle_outline,
          title: 'All caught up',
          text: 'There are no care-plan tasks right now.');
    }
    final t = Map<String, dynamic>.from(raw);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle_outline, color: MaatriTokens.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t['title'] as String? ?? 'Care task',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (t['detail'] != null) Text(t['detail'] as String),
                  TextButton(
                      onPressed: () => _complete(t),
                      child: const Text('Mark complete')),
                ])),
          ]),
        ),
      ),
    );
  }

  Widget _consent(String title, String detail, String type, bool locked) =>
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(detail),
          value: locked || (_consents[type] ?? false),
          onChanged: locked
              ? null
              : (value) async {
                  try {
                    await _api.setConsent(type, value);
                    if (mounted) setState(() => _consents[type] = value);
                  } catch (_) {
                    _message(
                        'We could not update this choice. Please try again.');
                  }
                });
  Widget _row(IconData icon, String title, String detail) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: MaatriTokens.primary),
      title: Text(title),
      subtitle: Text(detail));

  Widget _labStatus() {
    final labs = _data['lab_results'] as List<dynamic>? ?? const [];
    if (labs.isEmpty) {
      return _healthAction(
          icon: Icons.biotech_outlined,
          title: 'Lab result follow-up',
          detail:
              'When your clinician recommends it, add confirmed gestational diabetes or thyroid results for review.',
          action: 'Add a result',
          onPressed: _openLabResults);
    }
    final latest = labs.first is Map
        ? Map<String, dynamic>.from(labs.first as Map)
        : const <String, dynamic>{};
    final needsReview = latest['reference_status'] == 'needs_clinician_review';
    return _healthAction(
        icon: Icons.pending_actions_outlined,
        title: needsReview
            ? 'Clinician follow-up recommended'
            : 'Lab result pending review',
        detail: needsReview
            ? 'Your care team recommends follow-up. Use the message feature for non-urgent questions.'
            : '${latest['category'] ?? 'Result'} • ${latest['review_status'] ?? 'pending clinician review'}',
        action: 'View / add result',
        onPressed: _openLabResults);
  }

  Widget _alertStatus() {
    final alerts = _data['active_alerts'] as List<dynamic>? ?? const [];
    final alert = alerts.isEmpty || alerts.first is! Map
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(alerts.first as Map);
    final severity = alert['severity'] as String? ?? 'normal';
    final (label, color, icon) = switch (severity) {
      'info' => (
          'Recheck required',
          MaatriTokens.warning,
          Icons.refresh_rounded
        ),
      'warning' => (
          'Clinical review recommended',
          MaatriTokens.warning,
          Icons.medical_services_outlined
        ),
      'critical' => (
          'Urgent medical attention required',
          MaatriTokens.critical,
          Icons.warning_rounded
        ),
      _ => ('Normal', MaatriTokens.success, Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(alert.isEmpty
              ? 'No active care-team alert is shown.'
              : (alert['message'] as String? ??
                  'Follow the guidance from your care team.')),
        ])),
      ]),
    );
  }

  Widget _guidanceStatus() {
    final guidance = _data['guidance'] as List<dynamic>? ?? const [];
    if (guidance.isEmpty) return const SizedBox.shrink();
    final latest = guidance.first is Map
        ? Map<String, dynamic>.from(guidance.first as Map)
        : const <String, dynamic>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.verified_outlined, color: MaatriTokens.primary),
            SizedBox(width: 10),
            Text('Clinician-approved support',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Text(latest['title'] as String? ?? 'Care-team guidance'),
          if (latest['body'] is String) ...[
            const SizedBox(height: 4),
            Text(latest['body'] as String),
          ],
          const SizedBox(height: 6),
          const Text(
              'Follow the plan agreed with your clinician or dietitian. Do not change medicines based on this app.',
              style: TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _activityStatus() {
    final activity = _map(_data['activity']);
    final clearance = activity['activity_clearance'] as String? ??
        _map(_data['clinical_profile'])['activity_clearance'] as String? ??
        'not_recorded';
    final minutes = activity['today_minutes'] as int? ?? 0;
    return _healthAction(
      icon: Icons.directions_walk_outlined,
      title: 'Walking & activity',
      detail: clearance == 'cleared_by_clinician'
          ? '$minutes minutes recorded today. Wearable automatic tracking appears only after its classifier is validated.'
          : 'Ask your care team before starting or tracking a walking routine.',
      action: 'View activity',
      onPressed: _openActivity,
    );
  }

  Widget _healthAction({
    required IconData icon,
    required String title,
    required String detail,
    required String action,
    required VoidCallback onPressed,
  }) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: MaatriTokens.primary),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(detail),
                      TextButton(onPressed: onPressed, child: Text(action)),
                    ])),
              ])));

  Future<void> _showLabOnboarding() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.health_and_safety_outlined,
            color: MaatriTokens.primary),
        title: const Text('A quick health reminder'),
        content: const Text(
            'At the time recommended by your clinician, please complete gestational diabetes and thyroid testing. You can add confirmed values here for clinician review. This app will not diagnose a result or create a diet plan on its own.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I understand')),
        ],
      ),
    );
    try {
      await _api.acknowledgeLabOnboarding();
    } catch (_) {
      // It is safe to show the reminder again if a connection prevents the
      // acknowledgement from being saved.
      _labPromptShown = false;
    }
  }

  Future<void> _openLabResults() async {
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PatientLabResultPage(api: _api)));
    if (saved == true) await _load();
  }

  Future<void> _openWellbeing() async {
    final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PatientWellbeingPage(api: _api)));
    if (sent == true) await _load();
  }

  Future<void> _openMessages() async {
    await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => PatientCareMessagesPage(api: _api)));
    await _load();
  }

  Future<void> _openAssistant() async {
    await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => CompanionPage(api: _api)));
  }

  Future<void> _openActivity() async {
    await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => PatientActivityPage(api: _api)));
    await _load();
  }

  Future<void> _openClinicalProfile() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => PatientClinicalProfilePage(api: _api)));
    await _load();
  }

  Future<void> _complete(Map task) async {
    final id = task['id'] as String?;
    if (id == null) return;
    try {
      await _api.completeTask(id, 'completed');
      await _load();
    } catch (_) {
      _message('This task will be updated when you are back online.');
    }
  }

  Future<void> _sos() async {
    final note = await _dialog('Request urgent help',
        'Tell us anything your care team should know (optional).');
    if (note == null) return;
    try {
      await _api.sos(note);
      _message(
          'Help request sent. If this is life-threatening, call emergency services now.');
    } catch (_) {
      _message(
          'We could not send this request. Call emergency services or your care team now.');
    }
  }

  Future<void> _report() async {
    final choice = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _Symptoms());
    if (choice == null) return;
    try {
      final result = await _api.symptoms(choice, '');
      _message(result['urgent'] == true
          ? 'Urgent report sent. Seek medical care now.'
          : 'Your report was sent to your care team.');
    } catch (_) {
      _message(
          'Unable to send now. Please call your care team if you need help.');
    }
  }

  Future<String?> _dialog(String title, String hint) {
    final c = TextEditingController();
    return showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: c,
                    maxLength: 500,
                    decoration: InputDecoration(hintText: hint)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, c.text),
                      child: const Text('Send'))
                ]));
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  String _first(Object? name) => (name as String? ?? 'there').split(' ').first;
  String _reading(Map<String, dynamic> vital, String key, String unit) {
    if (!_fresh(vital) || vital[key] is! num) return 'Not currently available';
    return '${vital[key]} $unit';
  }

  bool _fresh(Map<String, dynamic> vital) {
    if (vital['is_fresh'] is bool) return vital['is_fresh'] as bool;
    if (vital['measurement_quality'] == 'unavailable' ||
        vital['contact_detected'] == false) {
      return false;
    }
    final raw = vital['captured_at'] ?? vital['observed_at'];
    final captured = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    return captured != null &&
        DateTime.now().toUtc().difference(captured) <=
            const Duration(minutes: 10);
  }

  bool _hasValidatedBloodPressure(Map<String, dynamic> vital) {
    const sources = {'validated_cuff', 'clinician_entered'};
    return sources.contains(vital['blood_pressure_source']) &&
        vital['systolic_bp'] is num &&
        vital['diastolic_bp'] is num;
  }

  String _source(Object? raw) => switch (raw) {
        'wearable_ppg' => 'MAX30102 PPG',
        'wearable_skin_adjacent' => 'TMP117 device / skin-adjacent',
        'validated_cuff' => 'Validated cuff',
        'external_validated_device' => 'Validated external device',
        'clinician_entered' => 'Clinician-entered',
        _ => 'Source unavailable',
      };

  String _readingContext(Map<String, dynamic> vital, String source) {
    final raw = vital['observed_at'] ?? vital['captured_at'];
    final observed = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    final time = observed == null
        ? 'observation time unavailable'
        : 'observed ${observed.hour.toString().padLeft(2, '0')}:${observed.minute.toString().padLeft(2, '0')}';
    final freshness = switch (vital['freshness']) {
      'current' => 'current',
      'stale' => 'stale',
      'unavailable' => 'unavailable',
      _ => _fresh(vital) ? 'current' : 'unavailable',
    };
    return '$source • $time • $freshness';
  }

  String _days(Object? date) {
    final d = date is String ? DateTime.tryParse(date) : null;
    return d == null
        ? 'Your maternal care companion'
        : '${DateTime.now().difference(d).inDays.clamp(0, 366)} days since delivery';
  }
}

class _Safety extends StatelessWidget {
  const _Safety({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xffFFF1EE),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.health_and_safety_outlined,
                    color: MaatriTokens.critical),
                SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Need help now?',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('See warning signs or send an SOS request.')
                    ]))
              ]))));
}

class _Vital extends StatelessWidget {
  const _Vital(this.label, this.value, this.context, this.icon, this.color);
  final String label, value, context;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: (MediaQuery.sizeOf(context).width - 50) / 2,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(height: 10),
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 3),
                    Text(this.context,
                        style: Theme.of(context).textTheme.labelSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis)
                  ]))));
}

class _AccountAccessDenied extends StatelessWidget {
  const _AccountAccessDenied({required this.message, this.onSignOut});
  final String message;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_person_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text('Account access needed',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    'Please contact your hospital care team. Do not rely on this app until access is restored.',
                    textAlign: TextAlign.center,
                  ),
                  if (onSignOut != null) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => onSignOut!(),
                      icon: const Icon(Icons.logout_outlined),
                      label: const Text('Sign out'),
                    )
                  ]
                ]),
              ),
            ),
          ),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text))
          ])));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            Icon(icon, size: 36, color: MaatriTokens.primary),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(text, textAlign: TextAlign.center)
          ])));
}

class _Symptoms extends StatefulWidget {
  const _Symptoms();
  @override
  State<_Symptoms> createState() => _SymptomsState();
}

class _SymptomsState extends State<_Symptoms> {
  final selected = <String>{};
  static const items = {
    'heavy_bleeding': 'Heavy bleeding',
    'breathing': 'Trouble breathing or chest pain',
    'headache': 'Severe headache or vision change',
    'fever': 'Fever or feeling very unwell',
    'mental_health': 'Feeling unsafe or thoughts of harm',
    'other': 'Something else worries me'
  };
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What are you feeling?',
                    style: Theme.of(context).textTheme.titleLarge),
                const Text('Select anything that applies.'),
                ...items.entries.map((e) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(e.key),
                    onChanged: (v) => setState(() => v == true
                        ? selected.add(e.key)
                        : selected.remove(e.key)),
                    title: Text(e.value))),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(context, selected.toList()),
                        child: const Text('Send to care team')))
              ])));
}
