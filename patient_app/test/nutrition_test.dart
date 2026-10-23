import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/features/patient/nutrition_page.dart';

class _Api extends PatientApi {
  _Api() : super(baseUrl: 'https://test.invalid');
  @override
  Future<Map<String, dynamic>> reportAnalyses() async => {'items': []};
  @override
  Future<Map<String, dynamic>> nutrition() async => {
    'preferences': {
      'diet': 'vegetarian',
      'allergens': [],
      'dislikes': [],
      'allergies_confirmed': false,
    },
    'plan': null,
    'catalog': [],
    'allergens': ['milk', 'wheat'],
  };
}

void main() {
  testWidgets(
    'nutrition starts with warm visuals and explicit report prerequisite',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: NutritionPage(api: _Api())));
      await tester.pumpAndSettle();
      expect(find.text('Food that fits you'), findsOneWidget);
      expect(find.text('Start with your food preferences'), findsOneWidget);
      expect(find.text('Analyse & suggest foods'), findsNothing);
      expect(find.text('Your week'), findsNothing);
    },
  );
  testWidgets('allergy preferences need explicit confirmation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: NutritionPage(api: _Api())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Food preferences'));
    await tester.pumpAndSettle();
    expect(
      find.text('Let’s get to know your food preferences'),
      findsOneWidget,
    );
    expect(find.text('Do you enjoy sweet foods?'), findsOneWidget);
    expect(find.text('Morning sickness or nausea?'), findsOneWidget);

    final scroll = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last;
    await tester.scrollUntilVisible(
      find.text('I have checked my allergies and preferences'),
      300,
      scrollable: scroll,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
  });
}
