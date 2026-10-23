import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/core/patient_realtime.dart';
import 'package:maatriwatch_patient_app/features/patient/patient_home.dart';
import 'package:maatriwatch_patient_app/main.dart';

class _PatientApi extends PatientApi {
  _PatientApi({this.denied = false})
      : super(baseUrl: 'https://api.example/api/v1');

  final bool denied;

  @override
  Future<Map<String, dynamic>> home() async {
    if (denied) throw const PatientApiException('Account is not linked.', 403);
    return {
      'patient': {
        'id': 'patient-test-id',
        'hospital_id': 'hospital-test-id',
        'full_name': 'Test Patient',
      },
      'latest_vital': {
        'heart_rate_bpm': 74,
        'spo2_percent': 98,
        'skin_adjacent_temperature_c': 35.8,
        'heart_rate_source': 'wearable_ppg',
        'spo2_source': 'wearable_ppg',
        'temperature_source': 'wearable_skin_adjacent',
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'freshness': 'current',
        'is_fresh': true,
      },
      'device_health': {'title': 'Wearable connected'},
      'care_plan': const [],
      'danger_signs': const [],
    };
  }

  @override
  Future<Map<String, dynamic>> consents() async => {'items': const []};
}

class _LiveVitals implements PatientLiveVitalsSource {
  final controller = StreamController<Map<String, dynamic>?>.broadcast();

  @override
  Stream<Map<String, dynamic>?> latestForPatient({
    required String hospitalId,
    required String patientId,
  }) =>
      controller.stream;
}

void main() {
  testWidgets('blocks use when the patient app has no secure configuration',
      (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());
    await tester.pump();
    expect(find.text('MaatriWatch setup needed'), findsOneWidget);
    expect(
        find.textContaining('Do not use an unconfigured app'), findsOneWidget);
  });

  testWidgets('debug configuration state offers an explicit presentation demo',
      (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());
    await tester.pump();
    await tester.tap(find.text('Run presentation demo'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to MaatriWatch'), findsOneWidget);
    expect(find.text('DEMO'), findsOneWidget);
  });

  testWidgets('displays a supplied configuration error', (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp(
      initializationError: 'Secure configuration is required.',
    ));
    await tester.pump();
    expect(find.text('Secure configuration is required.'), findsOneWidget);
  });

  testWidgets('labels wearable readings with source and observation state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: PatientHome(api: _PatientApi())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('PPG-derived heart rate'), 150);
    expect(find.text('PPG-derived heart rate'), findsOneWidget);
    expect(find.textContaining('MAX30102 PPG'), findsWidgets);
    expect(find.text('Device / skin-adjacent temperature'), findsOneWidget);
  });

  testWidgets('uses the Firebase live vital overlay when it arrives',
      (tester) async {
    final liveVitals = _LiveVitals();
    await tester.pumpWidget(MaterialApp(
        home: PatientHome(api: _PatientApi(), liveVitals: liveVitals)));
    await tester.pumpAndSettle();
    liveVitals.controller.add({
      'heart_rate_bpm': 81,
      'spo2_percent': 97,
      'skin_adjacent_temperature_c': 34.2,
      'heart_rate_source': 'wearable_ppg',
      'spo2_source': 'wearable_ppg',
      'temperature_source': 'wearable_skin_adjacent',
      'contact_detected': true,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'freshness': 'current',
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('81 bpm'), 150);
    expect(find.text('81 bpm'), findsOneWidget);
    expect(find.text('97 %'), findsOneWidget);
    await liveVitals.controller.close();
  });

  testWidgets('shows an account-access state instead of offline fallback',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: PatientHome(api: _PatientApi(denied: true))));
    await tester.pumpAndSettle();
    expect(find.text('Account access needed'), findsOneWidget);
    expect(find.text('Account is not linked.'), findsOneWidget);
  });
}
