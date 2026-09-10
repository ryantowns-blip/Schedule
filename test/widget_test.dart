import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atc_schedule_manager/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Web Schedule Manager opens to saved schedule home',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AtcScheduleManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('Web Schedule Manager'), findsOneWidget);
    expect(find.text('No saved schedule yet'), findsOneWidget);
    expect(find.text('Get Schedule'), findsOneWidget);
  });

  testWidgets('Update Schedule screen starts WMT login flow',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AtcScheduleManagerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Update Schedule'), findsOneWidget);
    expect(find.text('Connect to WMT'), findsOneWidget);

    await tester.tap(find.text('Connect to WMT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 1 of 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'controller@faa.gov');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of 2'), findsOneWidget);
    expect(find.text('Open FAA MyAccess'), findsOneWidget);
  });
}
