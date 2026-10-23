import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/concern_recorder.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/features/patient/concerns_page.dart';

class _Api extends PatientApi {
  _Api() : super(baseUrl: 'https://test.invalid');
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>> concerns() async => {'items': []};
  @override
  Future<Map<String, dynamic>> saveConcern(Map<String, dynamic> values) async {
    saved = values;
    return {'guidance': 'Saved for follow-up.'};
  }
}

void main() {
  test('recorded PCM receives a valid mono WAV header', () {
    final result = wavBytes(Uint8List.fromList([1, 2, 3, 4]));
    expect(String.fromCharCodes(result.take(4)), 'RIFF');
    expect(ByteData.sublistView(result).getUint32(40, Endian.little), 4);
    expect(result.sublist(44), [1, 2, 3, 4]);
  });
  testWidgets(
      'manual concerns work without AI consent and require confirmation',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(MaterialApp(home: ConcernsPage(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'A recurring headache');
    final vertical = find
        .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first;
    await tester.scrollUntilVisible(find.text('Enter details myself'), 100,
        scrollable: vertical);
    await tester.tap(find.text('Enter details myself'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Symptom in your words'), 150,
        scrollable: vertical);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Symptom in your words'),
        'Headache');
    expect(api.saved, isNull);
    await tester.scrollUntilVisible(find.text('Confirm and save report'), 150,
        scrollable: vertical);
    await tester.tap(find.text('Confirm and save report'));
    await tester.pumpAndSettle();
    expect(api.saved?['confirmed'], true);
    expect(api.saved?['symptoms'][0]['name'], 'Headache');
  });
}
