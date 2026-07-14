import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:el_hakem/main.dart';

void main() {
  testWidgets('Splash renders the brand title', (WidgetTester tester) async {
    await tester.pumpWidget(const BedoonHabdApp());
    await tester.pump(const Duration(milliseconds: 500)); // entrance underway

    // The animated splash shows the gradient wordmark.
    expect(find.text('بدون هبد!'), findsOneWidget);

    // Dispose the tree to cancel the splash's auto-nav timer and pulse ticker,
    // keeping the test free of pending-timer / active-ticker errors.
    await tester.pumpWidget(const SizedBox());
  });
}
