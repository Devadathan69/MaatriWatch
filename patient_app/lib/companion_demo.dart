import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'core/patient_api.dart';
import 'features/patient/companion_page.dart';
import 'features/patient/concerns_page.dart';

/// Explicit local integration demo, separate from the original offline mock app.
void main() {
  if (kReleaseMode) {
    throw StateError('The connected companion demo is debug-only');
  }
  const url = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000/api/v1');
  runApp(MaterialApp(
    title: 'MaatriCare • synthetic demo',
    theme: maatriTheme(),
    home: _DemoHub(api: PatientApi(baseUrl: url, demoMode: true)),
  ));
}

class _DemoHub extends StatefulWidget {
  const _DemoHub({required this.api});
  final PatientApi api;
  @override
  State<_DemoHub> createState() => _DemoHubState();
}

class _DemoHubState extends State<_DemoHub> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          const SafeArea(
              bottom: false,
              child: Material(
                  color: Color(0xffF5E5CF),
                  child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                              'LOCAL DEMO • synthetic patient • no clinical monitoring',
                              textAlign: TextAlign.center))))),
          Expanded(
              child: IndexedStack(index: _index, children: [
            CompanionPage(api: widget.api),
            ConcernsPage(api: widget.api)
          ])),
        ]),
        bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.spa_outlined), label: 'Companion'),
              NavigationDestination(
                  icon: Icon(Icons.mic_none), label: 'Concerns')
            ]),
      );
}
