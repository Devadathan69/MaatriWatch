import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// A deliberately isolated presentation mode.
///
/// It has no Firebase or API fallback and can only be reached by a debug build
/// with `--dart-define=DEMO_MODE=true`. Every mock reading is visibly marked as
/// simulated so it can never be mistaken for a care device connection.
class DemoPatientSignIn extends StatefulWidget {
  const DemoPatientSignIn({super.key});

  @override
  State<DemoPatientSignIn> createState() => _DemoPatientSignInState();
}

class _DemoPatientSignInState extends State<DemoPatientSignIn> {
  static const email = 'demo.patient@maatriwatch.local';
  static const password = 'MaatriDemo2026!';
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _useDemoAccount() => setState(() {
        _email.text = email;
        _password.text = password;
        _error = null;
      });

  void _signIn() {
    if (_email.text.trim().toLowerCase() == email &&
        _password.text == password) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DemoPatientHome()),
      );
      return;
    }
    setState(() => _error = 'Use the demo credentials shown below.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _DemoBadge(),
                    const SizedBox(height: 28),
                    const Icon(Icons.favorite_rounded,
                        color: MaatriTokens.primary, size: 48),
                    const SizedBox(height: 16),
                    Text('Welcome to MaatriWatch',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                      'Patient companion presentation. This build contains simulated data only.',
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      onSubmitted: (_) => _signIn(),
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(color: MaatriTokens.critical)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _signIn,
                        child: const Text('Sign in to demo'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _useDemoAccount,
                        child: const Text('Fill demo credentials'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Demo account',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            SizedBox(height: 6),
                            SelectableText('demo.patient@maatriwatch.local'),
                            SelectableText('MaatriDemo2026!'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class DemoPatientHome extends StatefulWidget {
  const DemoPatientHome({super.key});

  @override
  State<DemoPatientHome> createState() => _DemoPatientHomeState();
}

class _DemoPatientHomeState extends State<DemoPatientHome> {
  final _random = Random(14);
  late Timer _timer;
  int _tab = 0;
  int _heartRate = 76;
  int _spo2 = 98;
  double _temperature = 35.9;
  int _battery = 86;
  List<double> _history = [72, 74, 73, 76, 75, 77, 76, 78];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() {
        _heartRate = 74 + _random.nextInt(7);
        _spo2 = 97 + _random.nextInt(3);
        _temperature = 35.7 + _random.nextDouble() * .5;
        _battery = max(20, _battery - (_random.nextInt(2)));
        // A new immutable list lets CustomPaint reliably detect a change.
        _history = [..._history.skip(1), _heartRate.toDouble()];
      });
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showFirstVisitPrompt());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _showFirstVisitPrompt() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.health_and_safety_outlined,
              color: MaatriTokens.primary),
          title: const Text('A quick health reminder'),
          content: const Text(
            'At the time recommended by your clinician, please complete gestational diabetes and thyroid testing. You can add confirmed values here for your care team to review.\n\nThis app will never diagnose a result or create a diet plan on its own.',
          ),
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('MaatriWatch'),
          actions: const [
            Padding(padding: EdgeInsets.only(right: 16), child: _DemoBadge())
          ],
        ),
        body:
            IndexedStack(index: _tab, children: [_home(), _care(), _profile()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.favorite_outline),
                selectedIcon: Icon(Icons.favorite),
                label: 'Care'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile'),
          ],
        ),
      );

  Widget _home() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Hello, Anjali',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Day 18 of your postpartum care plan'),
          const SizedBox(height: 16),
          const _DemoNotice(
            icon: Icons.science_outlined,
            text:
                'Presentation mode: all readings below are simulated and refresh every 4 seconds.',
          ),
          const SizedBox(height: 16),
          _watchCard(),
          const SizedBox(height: 20),
          Text('Latest watch readings',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _MetricCard(
              icon: Icons.favorite_rounded,
              tint: const Color(0xffC9546C),
              value: '$_heartRate bpm',
              label: 'PPG-derived heart rate',
              readingContext: 'MAX30102 PPG • simulated • now',
            ),
            _MetricCard(
              icon: Icons.air_rounded,
              tint: const Color(0xff317D9D),
              value: '$_spo2%',
              label: 'PPG-derived SpO₂',
              readingContext: 'MAX30102 PPG • simulated • now',
            ),
            _MetricCard(
              icon: Icons.thermostat_outlined,
              tint: const Color(0xffD8863F),
              value: '${_temperature.toStringAsFixed(1)}°C',
              label: 'Skin-adjacent temperature',
              readingContext: 'TMP117 • simulated • now',
            ),
            const _MetricCard(
              icon: Icons.monitor_heart_outlined,
              tint: Color(0xff7062A6),
              value: '118/76 mmHg',
              label: 'Blood pressure',
              readingContext: 'DEMO sample • not measured by watch',
            ),
          ]),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('Heart-rate trend',
                              style: Theme.of(context).textTheme.titleMedium)),
                      const Chip(label: Text('Live demo')),
                    ]),
                    const SizedBox(height: 2),
                    const Text('PPG-derived readings from the last 30 minutes'),
                    SizedBox(
                        height: 150,
                        child: CustomPaint(painter: _TrendPainter(_history))),
                    const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text('30 min ago'), Text('Now')]),
                  ]),
            ),
          ),
          const SizedBox(height: 20),
          _urgentHelpCard(),
        ],
      );

  Widget _watchCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: Color(0xffE5F4EF), shape: BoxShape.circle),
              child:
                  const Icon(Icons.watch_outlined, color: MaatriTokens.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MaatriWatch X1 connected',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Text('Simulated watch feed • last update just now'),
                  ]),
            ),
            Column(children: [
              const Icon(Icons.battery_5_bar),
              Text('$_battery%')
            ]),
          ]),
        ),
      );

  Widget _urgentHelpCard() => Material(
        color: const Color(0xffFFF1EE),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Get help now'),
              content: const Text(
                  'If this is an emergency, call your local emergency number or go to the nearest hospital. Do not wait for an app reply.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ),
          ),
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
                    Text(
                        'See urgent warning signs and contact your care team.'),
                  ])),
            ]),
          ),
        ),
      );

  Widget _care() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Your care', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text(
              'Small check-ins help you and your care team stay connected.'),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.menu_book_outlined,
            title: 'Daily care plan',
            detail:
                'View example diet, routine, and dietitian-review support after a care-team referral.',
            action: 'View care plan',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DemoCarePlanPage())),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.directions_walk_outlined,
            title: 'Activity tracker',
            detail:
                'Mark morning and evening movement tasks when your clinician has cleared activity.',
            action: 'Open activity tracker',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DemoActivityPage())),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.forum_outlined,
            title: 'Ask your care team',
            detail:
                'Send non-urgent questions without using a clinician’s personal phone number.',
            action: 'Ask a question',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DemoCareMessagesPage())),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.auto_awesome_outlined,
            title: 'MaatriCare AI',
            detail:
                'Try the local presentation preview of the general-education assistant.',
            action: 'Open MaatriCare AI',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DemoAssistantPage())),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.biotech_outlined,
            title: 'Lab result follow-up',
            detail:
                'Add confirmed gestational diabetes or thyroid values for clinician review.',
            action: 'Open lab follow-up',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DemoLabResultPage())),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.self_improvement_outlined,
            title: 'Twice-weekly wellbeing check-in',
            detail:
                'Five questions to help you ask for support. It is not a diagnosis or EPDS replacement.',
            action: 'Start check-in',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DemoWellbeingPage())),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.notifications_active_outlined,
            title: 'Monitoring and alerts',
            detail:
                'See the four care-team response levels used in this presentation.',
            action: 'View alert levels',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DemoAlertLevelsPage())),
          ),
          const SizedBox(height: 20),
          const _DemoNotice(
            icon: Icons.info_outline,
            text:
                'For clinical screening, the care team should use a validated tool such as the 10-item EPDS with a follow-up pathway. A positive safety response always needs immediate human assessment.',
          ),
        ],
      );

  Widget _profile() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('Anjali Nair'),
            subtitle: Text('Demo patient • MaatriWatch Community Hospital'),
          ),
          const Divider(),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                Icon(Icons.verified_user_outlined, color: MaatriTokens.primary),
            title: Text('Presentation account'),
            subtitle: Text(
                'No personal health information or real clinician messages are used.'),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.badge_outlined,
            title: 'Health profile and device comparison',
            detail:
                'Record patient-reported history and compare a wearable reading with an actual reference device.',
            action: 'Open profile',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DemoProfileAndValidationPage())),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const DemoPatientSignIn()),
              (_) => false,
            ),
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Sign out of demo'),
          ),
        ],
      );
}

class DemoLabResultPage extends StatefulWidget {
  const DemoLabResultPage({super.key});
  @override
  State<DemoLabResultPage> createState() => _DemoLabResultPageState();
}

class _DemoLabResultPageState extends State<DemoLabResultPage> {
  String _category = 'Gestational diabetes';
  bool _saved = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Lab result follow-up')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const _DemoNotice(
            icon: Icons.privacy_tip_outlined,
            text:
                'For the presentation, “Use demo report” simulates a patient-confirmed upload. A real version must show extracted values for confirmation and keep every result pending clinician review.',
          ),
          const SizedBox(height: 16),
          Text('Which result do you have?',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'Gestational diabetes', label: Text('Glucose')),
              ButtonSegment(value: 'Thyroid', label: Text('Thyroid')),
            ],
            selected: {_category},
            onSelectionChanged: (values) => setState(() {
              _category = values.first;
              _saved = false;
            }),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _category == 'Gestational diabetes'
                            ? '75 g OGTT demo report'
                            : 'Thyroid-function demo report',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_category == 'Gestational diabetes'
                        ? 'Fasting: 94 mg/dL\n1 hour: 178 mg/dL\n2 hours: 144 mg/dL'
                        : 'TSH: 2.1 mIU/L\nFree T4: 1.1 ng/dL'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _saved = true),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Use demo report'),
                    ),
                  ]),
            ),
          ),
          if (_saved) ...[
            const SizedBox(height: 16),
            const _DemoNotice(
              icon: Icons.check_circle_outline,
              text:
                  'Result saved for clinician review. The app does not label it healthy/unhealthy, diagnose a condition, or generate a diet plan automatically.',
            ),
          ],
          const SizedBox(height: 20),
          const Text('Why clinician review?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const Text(
              'Glucose testing depends on the test protocol and timing. Thyroid interpretation needs the laboratory’s pregnancy- and trimester-specific reference range.'),
        ]),
      );
}

class DemoCarePlanPage extends StatefulWidget {
  const DemoCarePlanPage({super.key});

  @override
  State<DemoCarePlanPage> createState() => _DemoCarePlanPageState();
}

class _DemoCarePlanPageState extends State<DemoCarePlanPage> {
  bool _dietitianRequestSent = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Daily care plan')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const _DemoNotice(
            icon: Icons.info_outline,
            text:
                'Presentation example only. A personal diet or activity plan must be reviewed and assigned by the care team; this app does not diagnose gestational diabetes or thyroid disease.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Care-team plan preview',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                        'For a glucose-related follow-up, the care team may recommend regular meals, fibre-rich foods where appropriate, hydration, and review with a dietitian. The exact plan depends on the confirmed laboratory result, medicines, pregnancy stage, and clinician advice.'),
                  ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today’s supportive routine',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const _PlanRow(
                        'Keep meals regular, as advised by your care team.'),
                    const _PlanRow('Choose balanced meals and carry water.'),
                    const _PlanRow(
                        'Bring your confirmed report to the next review.'),
                    const _PlanRow(
                        'Do not change medicines based on this app.'),
                  ]),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => setState(() => _dietitianRequestSent = true),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Request dietitian review'),
          ),
          if (_dietitianRequestSent) ...[
            const SizedBox(height: 12),
            const _DemoNotice(
              icon: Icons.check_circle_outline,
              text:
                  'Demo request recorded. In the live app, the assigned care team receives this request and can add an approved plan.',
            ),
          ],
        ]),
      );
}

class _PlanRow extends StatelessWidget {
  const _PlanRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check_circle_outline,
              color: MaatriTokens.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}

class DemoActivityPage extends StatefulWidget {
  const DemoActivityPage({super.key});

  @override
  State<DemoActivityPage> createState() => _DemoActivityPageState();
}

class _DemoActivityPageState extends State<DemoActivityPage> {
  bool _morningDone = false;
  bool _eveningDone = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Activity tracker')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const _DemoNotice(
            icon: Icons.directions_walk_outlined,
            text:
                'Only follow activity guidance after clinician clearance. The wearable’s motion context supports a recheck after activity; it does not diagnose a problem or replace clinical assessment.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(children: [
              CheckboxListTile(
                value: _morningDone,
                onChanged: (value) =>
                    setState(() => _morningDone = value ?? false),
                title: const Text('Morning movement'),
                subtitle: const Text(
                    'Example task: gentle activity as approved by your care team'),
              ),
              const Divider(height: 1),
              CheckboxListTile(
                value: _eveningDone,
                onChanged: (value) =>
                    setState(() => _eveningDone = value ?? false),
                title: const Text('Evening movement'),
                subtitle: const Text(
                    'Example task: gentle activity as approved by your care team'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today’s progress',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                        value:
                            (_morningDone ? .5 : 0) + (_eveningDone ? .5 : 0)),
                    const SizedBox(height: 8),
                    Text(
                        '${(_morningDone ? 1 : 0) + (_eveningDone ? 1 : 0)} of 2 care tasks completed'),
                    const SizedBox(height: 8),
                    const Text(
                        'Wearable activity context: simulated for this presentation.'),
                  ]),
            ),
          ),
        ]),
      );
}

class DemoCareMessagesPage extends StatefulWidget {
  const DemoCareMessagesPage({super.key});

  @override
  State<DemoCareMessagesPage> createState() => _DemoCareMessagesPageState();
}

class _DemoCareMessagesPageState extends State<DemoCareMessagesPage> {
  final _message = TextEditingController();
  final List<String> _messages = [
    'Care team: Welcome. You can send non-urgent questions here.',
  ];

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _send() {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add('You: $text');
      _message.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ask your care team')),
        body: SafeArea(
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _DemoNotice(
                icon: Icons.forum_outlined,
                text:
                    'Demo inbox. In the live service, only your assigned hospital team can view and reply. Do not use messages for an emergency.',
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) => Align(
                  alignment: _messages[index].startsWith('You:')
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_messages[index])),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                    child: TextField(
                  controller: _message,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Write a non-urgent question'),
                )),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: _send, icon: const Icon(Icons.send)),
              ]),
            ),
          ]),
        ),
      );
}

class DemoAssistantPage extends StatefulWidget {
  const DemoAssistantPage({super.key});

  @override
  State<DemoAssistantPage> createState() => _DemoAssistantPageState();
}

class _DemoAssistantPageState extends State<DemoAssistantPage> {
  final _composer = TextEditingController();
  final List<_DemoChatMessage> _messages = [
    const _DemoChatMessage(
      text:
          'Hello. This is a local MaatriCare AI presentation preview. I can demonstrate general support questions, but I cannot see a medical record or live watch data.',
      mine: false,
    ),
  ];

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  String _answer(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('bleed') ||
        lower.contains('chest pain') ||
        lower.contains('breathe') ||
        lower.contains('harm')) {
      return 'Please seek emergency help now and do not wait for an app reply. Contact local emergency services, go to the nearest emergency department, or ask someone you trust to stay with you.';
    }
    if (lower.contains('diet') ||
        lower.contains('food') ||
        lower.contains('sugar')) {
      return 'A personal diet plan should be confirmed by your clinician or dietitian after reviewing the laboratory result. You can use the Daily care plan screen to request that review.';
    }
    if (lower.contains('walk') ||
        lower.contains('exercise') ||
        lower.contains('activity')) {
      return 'Only follow activity guidance after clinician clearance. The Activity tracker can help record a morning or evening task approved in a care plan.';
    }
    return 'For a personal question, use Ask your care team so an assigned clinician can reply. MaatriCare AI provides general education and does not diagnose or interpret watch readings.';
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_DemoChatMessage(text: text, mine: true));
      _messages.add(_DemoChatMessage(text: _answer(text), mine: false));
      _composer.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('MaatriCare AI')),
        body: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _DemoNotice(
              icon: Icons.auto_awesome_outlined,
              text:
                  'Local presentation preview. The hospital-issued app connects this screen to the authenticated server-side AI service; no API key is stored in this demo app.',
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final item = _messages[index];
                return Align(
                  alignment:
                      item.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: item.mine
                          ? const Color(0xffDDEFE9)
                          : const Color(0xffF1F4F4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(item.text),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: TextField(
                  controller: _composer,
                  maxLength: 800,
                  minLines: 1,
                  maxLines: 3,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                      hintText: 'Ask a general care question'),
                )),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: _send, icon: const Icon(Icons.send_rounded)),
              ]),
            ),
          ),
        ]),
      );
}

class _DemoChatMessage {
  const _DemoChatMessage({required this.text, required this.mine});
  final String text;
  final bool mine;
}

class DemoAlertLevelsPage extends StatelessWidget {
  const DemoAlertLevelsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Monitoring and alerts')),
        body: ListView(padding: const EdgeInsets.all(20), children: const [
          _DemoNotice(
            icon: Icons.info_outline,
            text:
                'Alert levels guide the care-team response. They are not diagnoses and should consider sensor quality, contact, time, and activity context.',
          ),
          SizedBox(height: 16),
          _AlertLevel('Normal', 'Continue the agreed monitoring plan.',
              Color(0xff2E7D5B)),
          _AlertLevel(
              'Recheck required',
              'Rest if appropriate and repeat the reading as guided.',
              Color(0xffB7791F)),
          _AlertLevel(
              'Clinical review recommended',
              'The care team should review the information.',
              Color(0xffC46B22)),
          _AlertLevel(
              'Urgent medical attention required',
              'Follow the care team’s urgent instructions or seek emergency help.',
              Color(0xffC94D4D)),
        ]),
      );
}

class _AlertLevel extends StatelessWidget {
  const _AlertLevel(this.title, this.detail, this.color);
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(Icons.circle, color: color, size: 18),
          title: Text(title),
          subtitle: Text(detail),
        ),
      );
}

class DemoProfileAndValidationPage extends StatefulWidget {
  const DemoProfileAndValidationPage({super.key});

  @override
  State<DemoProfileAndValidationPage> createState() =>
      _DemoProfileAndValidationPageState();
}

class _DemoProfileAndValidationPageState
    extends State<DemoProfileAndValidationPage> {
  bool _hypertensionHistory = false;
  bool _gdmHistory = false;
  bool _previousComplication = false;
  String _stage = 'Third trimester';
  final _referenceHeartRate = TextEditingController();
  final _referenceBloodPressure = TextEditingController();
  bool _comparisonSaved = false;

  @override
  void dispose() {
    _referenceHeartRate.dispose();
    _referenceBloodPressure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Health profile and comparison')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const _DemoNotice(
            icon: Icons.privacy_tip_outlined,
            text:
                'Profile entries are patient-reported until the clinician reviews them. This screen records a demonstration only; it does not change medical care.',
          ),
          const SizedBox(height: 16),
          Text('Pregnancy profile',
              style: Theme.of(context).textTheme.titleLarge),
          DropdownButtonFormField<String>(
            initialValue: _stage,
            decoration: const InputDecoration(labelText: 'Pregnancy stage'),
            items: const [
              'First trimester',
              'Second trimester',
              'Third trimester',
              'Postpartum'
            ]
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) => setState(() => _stage = value ?? _stage),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _hypertensionHistory,
            onChanged: (value) =>
                setState(() => _hypertensionHistory = value ?? false),
            title: const Text('Previous hypertension history'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _gdmHistory,
            onChanged: (value) => setState(() => _gdmHistory = value ?? false),
            title: const Text('Previous GDM / diabetes history'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _previousComplication,
            onChanged: (value) =>
                setState(() => _previousComplication = value ?? false),
            title: const Text('Previous pregnancy complication'),
          ),
          const SizedBox(height: 20),
          Text('Wearable comparison log',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
              'Enter values only from an actual reference device. The app never calculates blood pressure from PPG.'),
          const SizedBox(height: 12),
          TextField(
            controller: _referenceHeartRate,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Reference-device heart rate (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _referenceBloodPressure,
            decoration: const InputDecoration(
                labelText:
                    'Actual cuff blood pressure, e.g. 118/76 (optional)'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => setState(() => _comparisonSaved = true),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save comparison for review'),
          ),
          if (_comparisonSaved) ...[
            const SizedBox(height: 12),
            const _DemoNotice(
              icon: Icons.check_circle_outline,
              text: 'Demo comparison saved for clinician review.',
            ),
          ],
        ]),
      );
}

class DemoWellbeingPage extends StatefulWidget {
  const DemoWellbeingPage({super.key});
  @override
  State<DemoWellbeingPage> createState() => _DemoWellbeingPageState();
}

class _DemoWellbeingPageState extends State<DemoWellbeingPage> {
  static const regularAnswers = [
    'Never',
    'Some days',
    'Often',
    'Almost every day',
    'Prefer not to say'
  ];
  final Map<String, String> _answers = {};
  bool _guardianConsent = false;
  bool _sent = false;

  bool get _complete => _answers.length == 5;

  void _submit() {
    if (!_complete) return;
    if (_answers['safety'] == 'Yes') {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: MaatriTokens.critical),
          title: const Text('Please get immediate help'),
          content: Text(
            'In a configured care system, this response creates an urgent clinician alert${_guardianConsent ? ' and can notify your opted-in guardian' : ''}. For this demo, no real message is sent. Call local emergency services or go to the nearest hospital now; do not stay alone.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('I understand'))
          ],
        ),
      );
    }
    setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Wellbeing check-in')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const _DemoNotice(
            icon: Icons.favorite_border,
            text:
                'Suggested twice each week. These five support questions are not a diagnosis and do not replace the validated 10-item EPDS or clinician assessment.',
          ),
          const SizedBox(height: 16),
          const Text('Over the last few days…',
              style: TextStyle(fontWeight: FontWeight.w800)),
          _question(
              'mood',
              'How often have you felt low, sad, or emotionally drained?',
              regularAnswers),
          _question(
              'enjoyment',
              'How often have you found it hard to enjoy or look forward to things?',
              regularAnswers),
          _question(
              'overwhelmed',
              'How often have you felt overwhelmed by day-to-day tasks?',
              regularAnswers),
          _question(
              'support',
              'How often have you felt that you lacked the support you needed?',
              regularAnswers),
          _question(
              'safety',
              'Have you had thoughts of harming yourself, or felt unsafe?',
              const ['No', 'Yes', 'Prefer not to say']),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _guardianConsent,
            onChanged: (value) =>
                setState(() => _guardianConsent = value ?? false),
            title: const Text(
                'If I report an immediate safety concern, I consent to contacting my chosen guardian.'),
            subtitle: const Text(
                'Only available when the hospital has a verified, opted-in WhatsApp contact.'),
          ),
          const SizedBox(height: 8),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _complete ? _submit : null,
                  child: const Text('Send check-in'))),
          if (_sent)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: _DemoNotice(
                  icon: Icons.check_circle_outline,
                  text:
                      'Check-in saved in demo. A clinician reviews wellbeing concerns; the app does not diagnose postpartum depression.'),
            ),
        ]),
      );

  Widget _question(String key, String prompt, List<String> choices) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: DropdownButtonFormField<String>(
          initialValue: _answers[key],
          decoration: InputDecoration(labelText: prompt),
          items: choices
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: (value) => setState(() => _answers[key] = value ?? ''),
        ),
      );
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();
  @override
  Widget build(BuildContext context) => const Chip(
        avatar: Icon(Icons.science_outlined, size: 16),
        label: Text('DEMO'),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.icon,
      required this.tint,
      required this.value,
      required this.label,
      required this.readingContext});
  final IconData icon;
  final Color tint;
  final String value;
  final String label;
  final String readingContext;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.sizeOf(context).width - 50) / 2,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: tint),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(readingContext,
                  style: Theme.of(context).textTheme.labelSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(
      {required this.icon,
      required this.title,
      required this.detail,
      required this.action,
      required this.onTap});
  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: MaatriTokens.primary),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(detail),
            const SizedBox(height: 8),
            TextButton(onPressed: onTap, child: Text(action)),
          ]),
        ),
      );
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xffE5F4EF),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: MaatriTokens.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(List<double> points)
      : points = List<double>.unmodifiable(points);
  final List<double> points;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = MaatriTokens.border
      ..strokeWidth = 1;
    for (var y = 0.2; y < 1; y += .2) {
      canvas.drawLine(Offset(0, size.height * y),
          Offset(size.width, size.height * y), grid);
    }
    final minValue = points.reduce(min) - 3;
    final maxValue = points.reduce(max) + 3;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = size.width * index / (points.length - 1);
      final y = size.height -
          ((points[index] - minValue) / (maxValue - minValue) * size.height);
      index == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill, Paint()..color = MaatriTokens.primary.withValues(alpha: .12));
    canvas.drawPath(
        path,
        Paint()
          ..color = MaatriTokens.primary
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke);
    canvas.drawCircle(
        Offset(size.width, path.getBounds().top + path.getBounds().height),
        0,
        Paint());
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      !listEquals(oldDelegate.points, points);
}
