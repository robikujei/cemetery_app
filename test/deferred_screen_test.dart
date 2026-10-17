import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cemetery_app/widgets/deferred_screen.dart';

void main() {
  testWidgets('waits for code before building the screen', (tester) async {
    final ready = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredScreen(
          load: () {
            calls++;
            return ready.future;
          },
          builder: (_) => const Text('Loaded'),
        ),
      ),
    );
    expect(find.text('Loaded'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Loaded'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('failed download can be retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredScreen(
          load: () async {
            if (calls++ == 0) throw Exception('offline');
          },
          builder: (_) => const Text('Loaded'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Loaded'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded'), findsOneWidget);
    expect(calls, 2);
  });
}
