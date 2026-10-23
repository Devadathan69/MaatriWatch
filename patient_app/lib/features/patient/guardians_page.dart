import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/patient_api.dart';
import '../../core/device_reminders.dart';
import 'event_reminder_sheet.dart';

class PatientGuardiansPage extends StatefulWidget {
  const PatientGuardiansPage({super.key, required this.api});
  final PatientApi api;
  @override
  State<PatientGuardiansPage> createState() => _PatientGuardiansPageState();
}

class _PatientGuardiansPageState extends State<PatientGuardiansPage> {
  final _email = TextEditingController();
  List<Map> _guardians = [];
  Map<String, dynamic>? _invite;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.patientGuardians();
      if (mounted) {
        setState(
          () => _guardians = (data['items'] as List).whereType<Map>().toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _inviteGuardian() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.api.inviteGuardian(_email.text.trim());
      if (mounted) setState(() => _invite = value);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map guardian) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this guardian?'),
        content: const Text(
          'They will stop receiving new SOS notifications and lose access to your guardian inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep guardian'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.removeGuardian(guardian['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My SOS guardians')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Someone you trust, one tap away',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        const Text(
          'Link up to three trusted people. When you send an SOS, they get an in-app alert and a phone notification if enabled. This shares SOS requests, not your reports or conversations.',
        ),
        const SizedBox(height: 18),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final guardian in _guardians)
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(guardian['display_name'] as String? ?? 'Guardian'),
              subtitle: Text(guardian['email'] as String? ?? ''),
              trailing: IconButton(
                tooltip: 'Remove guardian',
                onPressed: () => _remove(guardian),
                icon: const Icon(Icons.link_off),
              ),
            ),
          ),
        if (_guardians.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No guardian is linked yet.'),
          ),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Guardian’s email address',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _inviteGuardian,
          icon: const Icon(Icons.add_link),
          label: Text(_busy ? 'Creating…' : 'Create private linking code'),
        ),
        if (_invite != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'For ${_invite!['email']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_invite!['code'] as String),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _invite!['code'] as String),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Linking code copied.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy code'),
                  ),
                  Text(
                    'Expires: ${reminderDate(context, _invite!['expires_at'])}',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ask your guardian to install MaatriWatch on their Android phone, choose guardian sign-in, verify this email, enter the code, and enable SOS notifications. The code works once and expires after 24 hours.',
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'Keep a direct emergency contact plan too. Notifications depend on internet, device permissions and availability.',
        ),
        TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh linked guardians'),
        ),
      ],
    ),
  );
}

class GuardianHome extends StatefulWidget {
  const GuardianHome({super.key, required this.api, required this.onSignOut});
  final PatientApi api;
  final Future<void> Function() onSignOut;
  @override
  State<GuardianHome> createState() => _GuardianHomeState();
}

class _GuardianHomeState extends State<GuardianHome> {
  final _code = TextEditingController();
  Map<String, dynamic> _home = {};
  String? _message;
  Timer? _poll;
  bool _busy = false, _loading = false;
  @override
  void initState() {
    super.initState();
    _start();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  Future<void> _start() async {
    await _load();
    try {
      await DeviceReminders.resumeGuardian(widget.api);
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await widget.api.guardianHome();
      if (mounted) setState(() => _home = data);
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      _loading = false;
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('MaatriWatch guardian'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Be there when she needs you',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          const Text(
            'Link using the private code shared by the patient. This account receives SOS requests, without access to medical reports or companion conversations.',
          ),
          const SizedBox(height: 18),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(_message!),
            ),
          for (final p in (_home['patients'] as List? ?? []).whereType<Map>())
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(p['full_name'] as String),
                subtitle: const Text('Linked for SOS support'),
              ),
            ),
          TextField(
            controller: _code,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Private linking code',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _act(() async {
                    await widget.api.linkGuardian(_code.text.trim());
                    _code.clear();
                  }),
            child: const Text('Link patient'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy || (_home['patients'] as List? ?? []).isEmpty
                ? null
                : () => _act(() async {
                    await DeviceReminders.enable(widget.api, guardian: true);
                    if (mounted) {
                      setState(
                        () => _message =
                            'SOS phone notifications enabled on this device.',
                      );
                    }
                  }),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Enable SOS notifications'),
          ),
          const SizedBox(height: 24),
          Text('SOS inbox', style: Theme.of(context).textTheme.titleLarge),
          if ((_home['notifications'] as List? ?? []).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'SOS requests from linked patients will appear here.',
              ),
            ),
          for (final n
              in (_home['notifications'] as List? ?? []).whereType<Map>())
            Card(
              color: n['read_at'] == null ? const Color(0xffFBE5DF) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sos, color: Color(0xffA13734)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${n['full_name']} requested urgent help',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(reminderDate(context, n['created_at'])),
                    const SizedBox(height: 8),
                    const Text(
                      'Contact them now and follow your agreed emergency plan. For immediate danger, contact emergency services.',
                    ),
                    if (n['read_at'] == null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _act(() async {
                                await widget.api.readGuardianNotification(
                                  n['id'] as String,
                                );
                              }),
                        child: const Text('Mark as seen'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
