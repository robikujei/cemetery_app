import 'package:cemetery_app/widgets/batch_save_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('minimize keeps progress live and does not request stop', (
    tester,
  ) async {
    final progress = ValueNotifier('Saving lots · 8 / 32 confirmed saved');
    var minimized = false;
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => Align(
              alignment: Alignment.topRight,
              child: BatchSaveProgress(
                progress: progress,
                minimized: minimized,
                onToggleSize: () => update(() => minimized = !minimized),
                onStop: () => stops++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Minimize'));
    await tester.pump();
    expect(minimized, isTrue);
    expect(stops, 0);
    expect(find.byTooltip('Expand save progress'), findsOneWidget);
    expect(find.text('Stop after current group'), findsNothing);
    progress.value = 'Saving lots · 16 / 32 confirmed saved';
    await tester.pump();
    expect(find.text(progress.value), findsOneWidget);
    await tester.tap(find.byTooltip('Expand save progress'));
    await tester.pump();
    expect(minimized, isFalse);
    expect(stops, 0);
    await tester.tap(find.text('Stop after current group'));
    expect(stops, 1);
    await tester.pumpWidget(const SizedBox());
    progress.dispose();
  });

  testWidgets('compact progress fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = ValueNotifier(
      'Recording changes · 500 / 500 confirmed saved',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: BatchSaveProgress(
              progress: progress,
              minimized: true,
              onToggleSize: () {},
              onStop: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    progress.dispose();
  });
}
