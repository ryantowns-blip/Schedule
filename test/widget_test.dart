import 'package:flutter_test/flutter_test.dart';
import 'package:atc_schedule_manager/main.dart';

void main() {
  testWidgets('ATC Schedule Manager launches', (WidgetTester tester) async {
    await tester.pumpWidget(const AtcScheduleManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('ATC Schedule Manager'), findsOneWidget);
    expect(find.text('Parse schedule'), findsOneWidget);
  });
}
