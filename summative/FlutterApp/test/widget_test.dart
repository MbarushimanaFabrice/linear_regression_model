import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:absenteeism_predictor/main.dart';

void main() {
  testWidgets('page shows the Predict button and the result area', (WidgetTester tester) async {
    await tester.pumpWidget(const AbsenteeismApp());
    expect(find.text('Predict'), findsOneWidget);
    expect(find.byKey(const Key('result_text')), findsOneWidget);
  });
}
