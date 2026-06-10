import 'package:flutter_test/flutter_test.dart';

import 'package:cmbank_interest_calculator/app/app.dart';

void main() {
  testWidgets('CM Bank app shows startup flow', (WidgetTester tester) async {
    await tester.pumpWidget(const CMBankApp());

    expect(find.byType(CMBankApp), findsOneWidget);
  });
}
