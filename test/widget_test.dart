import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Basic widget test', (WidgetTester tester) async {
    // Create a simple test widget
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Hello, World!'),
          ),
        ),
      ),
    );

    // Verify that the text is displayed
    expect(find.text('Hello, World!'), findsOneWidget);
  });

  testWidgets('Button interaction test', (WidgetTester tester) async {
    bool buttonPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                buttonPressed = true;
              },
              child: Text('Press Me'),
            ),
          ),
        ),
      ),
    );

    // Verify button is present
    expect(find.text('Press Me'), findsOneWidget);

    // Tap the button
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Verify button was pressed
    expect(buttonPressed, isTrue);
  });
} 