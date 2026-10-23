import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/core/video_html.dart';
import 'package:maatriwatch_patient_app/features/patient/consultations_page.dart';

class _Api extends PatientApi {
  _Api() : super(baseUrl: 'https://test.invalid');
  bool booked = false;
  Map<String, dynamic> get slot => {
        'id': 'test-slot',
        'clinician_name': 'Care team clinician',
        'start_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'end_at': DateTime.now()
            .add(const Duration(days: 1, minutes: 30))
            .toUtc()
            .toIso8601String()
      };
  @override
  Future<Map<String, dynamic>> consultationSlots() async => {
        'items': booked ? [] : [slot]
      };
  @override
  Future<Map<String, dynamic>> consultations() async => {
        'items': booked
            ? [
                {...slot, 'id': 'visit', 'status': 'booked'}
              ]
            : [],
        'video_configured': false
      };
  @override
  Future<Map<String, dynamic>> bookConsultation(
      String slotId, String reason) async {
    booked = true;
    return {};
  }
}

void main() {
  test(
      'video embed rejects external/cleartext rooms and keeps tokens out of URLs',
      () {
    expect(() => videoHtml('http://example.com/room', 'token'),
        throwsArgumentError);
    final html = videoHtml('https://demo.daily.co/private-room', 'test-token');
    expect(html, contains('frame.join('));
    expect(html, isNot(contains('?t=')));
    expect(html, contains('no-referrer'));
    final escaped = videoHtml(
        'https://demo.daily.co/private-room', '</script><script>bad</script>');
    expect(escaped, isNot(contains('</script><script>bad')));
  });
  testWidgets(
      'booking is confirmed explicitly and video availability stays honest',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(MaterialApp(home: ConsultationsPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Video calling needs'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Book'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    expect(api.booked, false);
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(api.booked, true);
  });
}
