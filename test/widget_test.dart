import 'package:flutter_test/flutter_test.dart';
import 'package:grandma_pill_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows all eight entries on a phone', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GrandmaPillTrackerApp());
    await tester.pumpAndSettle();

    expect(find.text('Today’s checklist'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(8));
  });

  testWidgets('uses a two-column checklist on desktop', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GrandmaPillTrackerApp());
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(8));
  });
}
