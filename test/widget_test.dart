import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atc_schedule_manager/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Web Schedule Manager opens to screenshot import home',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AtcScheduleManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('Web Schedule Manager'), findsOneWidget);
    expect(find.text('Your schedule starts here'), findsOneWidget);
    expect(find.text('Import Schedule Screenshots'), findsOneWidget);
    expect(find.text('Import Upcoming Leave'), findsOneWidget);
  });
}
