import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atc_schedule_manager/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ATC Schedule Manager opens to screenshot import home',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AtcScheduleManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('ATC Schedule Manager'), findsOneWidget);
    expect(find.text('No schedule imported yet'), findsOneWidget);
    expect(find.text('Import Schedule Screenshots'), findsOneWidget);
  });
}
