import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'core/patient_api.dart';
import 'features/patient/companion_page.dart';

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
    home: Scaffold(
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
          child: CompanionPage(api: PatientApi(baseUrl: url, demoMode: true))),
    ])),
  ));
}
