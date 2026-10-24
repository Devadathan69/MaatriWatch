import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/features/auth/auth_gate.dart';

void main() {
  for (final resume in [false, true]) {
    testWidgets(
      'recovers from a refused connection on ${resume ? 'resume' : 'retry'}',
      (tester) async {
        var accessRequests = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/account/access')) {
            accessRequests++;
            if (accessRequests == 1) {
              throw http.ClientException(
                'Connection refused: 127.0.0.1:8000 private transport details',
              );
            }
            return http.Response(jsonEncode({'patient': false}), 200);
          }
          return http.Response(
            jsonEncode({'patients': [], 'notifications': []}),
            200,
          );
        });
        final api = PatientApi(
          client: client,
          baseUrl: 'http://127.0.0.1:8000/api/v1',
          demoMode: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AccountAccessGate(api: api, onSignOut: () async {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Let’s reconnect'), findsOneWidget);
        expect(find.textContaining('127.0.0.1'), findsNothing);
        expect(find.textContaining('ClientException'), findsNothing);
        expect(accessRequests, 1);
        if (resume) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          await tester.tap(find.text('Try again'));
        }
        await tester.pumpAndSettle();
        expect(accessRequests, 2);
        expect(find.text('MaatriWatch guardian'), findsOneWidget);
        expect(find.text('Let’s reconnect'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
  }

  testWidgets('an unresponsive account service offers retry after 75 seconds', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    await tester.pumpWidget(
      MaterialApp(
        home: AccountAccessGate(
          api: PatientApi(
            client: client,
            baseUrl: 'https://test.invalid',
            demoMode: true,
          ),
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 76));
    await tester.pumpAndSettle();
    expect(find.text('Let’s reconnect'), findsOneWidget);
    expect(find.textContaining('taking too long'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete(http.Response('{}', 200));
    client.close();
  });

  testWidgets(
    'an authorization failure retains the account access restriction',
    (tester) async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'Email verification is required.'}),
          403,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AccountAccessGate(
            api: PatientApi(
              client: client,
              baseUrl: 'https://test.invalid',
              demoMode: true,
            ),
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Email verification is required.'), findsOneWidget);
      expect(find.text('Let’s reconnect'), findsNothing);
      expect(find.text('MaatriWatch guardian'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
}
