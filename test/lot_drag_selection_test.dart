import 'package:cemetery_app/widgets/lot_drag_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'drag selects an area in local map coordinates in either direction',
    (tester) async {
      final selections = <Rect>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: SizedBox(
                  width: 400,
                  height: 300,
                  child: LotDragSelection(onSelected: selections.add),
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(LotDragSelection));
      await tester.dragFrom(
        origin + const Offset(50, 50),
        const Offset(150, 100),
      );
      await tester.pump();
      expect(selections.single, const Rect.fromLTRB(50, 50, 200, 150));
      await tester.dragFrom(
        origin + const Offset(200, 150),
        const Offset(-150, -100),
      );
      await tester.pump();
      expect(selections.last, selections.first);
    },
  );

  testWidgets('tap alone does not create a selection', (tester) async {
    final selections = <Rect>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: LotDragSelection(onSelected: selections.add),
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    expect(selections, isEmpty);
  });
}
