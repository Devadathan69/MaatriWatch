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
      expect(find.text('Upload audio'), findsNothing);
      expect(find.text('Your recording as text'), findsNothing);
      final vertical = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Symptom'),
        150,
        scrollable: vertical,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Symptom'),
        'Headache',
      );
      expect(api.saved, isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save to my history'),
        150,
        scrollable: vertical,
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save to my history'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save to my history'));
      await tester.pumpAndSettle();
      expect(api.saved?['confirmed'], true);
      expect(api.saved?['entry_mode'], 'manual');
      expect(api.saved?['original_text'], '');
      expect(api.saved?['symptoms'][0]['name'], 'Headache');
    },
  );
}
