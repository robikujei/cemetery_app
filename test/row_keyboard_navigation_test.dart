import 'package:cemetery_app/widgets/row_keyboard_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('focused map handles arrows but input fields retain their keys', (
    tester,
  ) async {
    final focus = FocusNode();
    final directions = <Offset>[];
    final text = TextEditingController(text: '001');
    await tester.pumpWidget(
      MaterialApp(
        home: RowKeyboardNavigation(
          focusNode: focus,
          enabled: true,
          onDirection: directions.add,
          child: Scaffold(body: TextField(controller: text)),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(directions, [const Offset(1, 0), const Offset(0, 1)]);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(directions.length, 2);
    expect(text.text, '001');
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(directions.last, const Offset(0, -1));
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    text.dispose();
  });
  testWidgets('disabled navigation does not add lots', (tester) async {
    final focus = FocusNode();
    final directions = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RowKeyboardNavigation(
          focusNode: focus,
          enabled: false,
          onDirection: directions.add,
          child: const Scaffold(),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(directions, isEmpty);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });
}
