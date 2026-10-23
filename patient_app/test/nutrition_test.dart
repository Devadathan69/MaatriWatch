import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/features/patient/nutrition_page.dart';
import 'package:maatriwatch_patient_app/features/patient/food_art.dart';

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
          'allergies_confirmed': false
        },
        'plan': null,
        'catalog': [],
        'allergens': ['milk', 'wheat']
      };
}

void main() {
  testWidgets(
      'nutrition starts with warm visuals and explicit report prerequisite',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: NutritionPage(api: _Api())));
    await tester.pumpAndSettle();
    expect(find.text('NOURISH & NURTURE'), findsOneWidget);
    expect(find.byType(FoodArt), findsOneWidget);
    expect(find.textContaining('one meal at a time.'), findsOneWidget);
    expect(
        find.textContaining('Start with a confirmed report'), findsOneWidget);
  });
  testWidgets('allergy preferences need explicit confirmation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: NutritionPage(api: _Api())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Food preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Made around your needs'), findsOneWidget);
    expect(find.text('milk'), findsOneWidget);
    final checkbox =
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.value, false);
  });
}
