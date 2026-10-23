import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/features/patient/companion_page.dart';

class _Api extends PatientApi {
  _Api() : super(baseUrl: 'https://test.invalid/api/v1');
  final prefs = <String, dynamic>{
    'memory_enabled': false,
    'context_enabled': false,
    'language': 'en'
  };
  @override
  Future<Map<String, dynamic>> companion() async => {
        'preferences': prefs,
        'messages': [],
        'memories': [],
        'reminders': [],
        'notifications': []
      };
  @override
  Future<Map<String, dynamic>> checkReminders() async => {'notifications': []};
  @override
  Future<Map<String, dynamic>> companionChat(String message) async => {
        'answer':
            'That sounds like a tiring day. Would you like to talk about it?',
        'urgent': false
      };
  @override
  Future<Map<String, dynamic>> companionPreferences(
      Map<String, dynamic> values) async {
    prefs.addAll(values);
    return {};
  }
}

void main() {
  testWidgets('companion sends a message and displays the reply',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: CompanionPage(api: _Api())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'I am tired today');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('I am tired today'), findsOneWidget);
    expect(find.textContaining('That sounds like'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('memory controls default off and can be explicitly enabled',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(MaterialApp(home: CompanionPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Memory and language'));
    await tester.pumpAndSettle();
    expect(find.text('Your memory, your choice'), findsOneWidget);
    expect(api.prefs['memory_enabled'], false);
    await tester.tap(find.text('Remember our conversations'));
    await tester.pumpAndSettle();
    expect(api.prefs['memory_enabled'], true);
    await tester.pumpWidget(const SizedBox());
  });
}
