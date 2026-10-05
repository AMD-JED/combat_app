import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:combat_app_frontend/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CombatSportsApp()),
    );
    // `MaterialApp.router` is a named constructor of MaterialApp, so the
    // widget tree contains exactly one MaterialApp.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
