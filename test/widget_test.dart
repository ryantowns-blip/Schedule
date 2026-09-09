import 'package:flutter_test/flutter_test.dart';
import 'package:atc_schedule_manager/main.dart';

void main() {
  testWidgets('ATC Schedule Manager launches', (WidgetTester tester) async {
    await tester.pumpWidget(const AtcScheduleManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('ATC Schedule Manager'), findsOneWidget);
    expect(find.text('WMT Scheduler'), findsOneWidget);
    expect(find.text('Connect to WMT'), findsOneWidget);
    expect(find.text('Parse schedule'), findsOneWidget);
  });

  testWidgets('WMT login advances from email to MyAccess password step',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AtcScheduleManagerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect to WMT'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 1 of 2'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'controller@faa.gov');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of 2'), findsOneWidget);
    expect(find.text('Open FAA MyAccess'), findsOneWidget);
  });
}
