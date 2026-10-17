import 'package:cemetery_app/widgets/lazy_screen_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'loads screens on demand and preserves state with inactive tickers muted',
    (tester) async {
      final initialized = <int>[];
      Future<void> show(int index) => tester.pumpWidget(
        MaterialApp(
          home: LazyScreenStack(
            index: index,
            children: [
              for (var i = 0; i < 3; i++)
                _Screen(id: i, initialized: initialized),
            ],
          ),
        ),
      );
      await show(0);
      expect(initialized, [0]);
      await tester.tap(find.text('Count 0: 0'));
      await tester.pump();
      await show(1);
      expect(initialized, [0, 1]);
      final hidden = tester.element(
        find.text('Count 0: 1', skipOffstage: false),
      );
      expect(TickerMode.of(hidden), isFalse);
      await show(0);
      expect(find.text('Count 0: 1'), findsOneWidget);
      expect(initialized, [0, 1]);
      expect(TickerMode.of(tester.element(find.text('Count 0: 1'))), isTrue);
    },
  );
}

class _Screen extends StatefulWidget {
  const _Screen({required this.id, required this.initialized});
  final int id;
  final List<int> initialized;
  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    widget.initialized.add(widget.id);
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('Count ${widget.id}: $count'),
  );
}
