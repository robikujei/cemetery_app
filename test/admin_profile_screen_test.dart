import 'package:cemetery_app/models/app_user.dart';
import 'package:cemetery_app/providers/session_providers.dart';
import 'package:cemetery_app/screens/admin/admin_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  Future<void> openProfile(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => const AppUser(
              id: 'admin',
              displayName: 'Administrator',
              role: UserRole.admin,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AdminProfileScreen())),
      ),
    );
  }

  testWidgets('prefills name, keeps email read-only and rejects blank name', (
    tester,
  ) async {
    await openProfile(tester);
    final fields = find.byType(TextFormField);
    expect(find.text('Administrator'), findsOneWidget);
    expect(tester.widget<TextFormField>(fields.at(1)).initialValue, '');
    final emailInput = find.descendant(
      of: fields.at(1),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(emailInput).readOnly, isTrue);
    await tester.enterText(fields.first, '   ');
    await tester.tap(find.text('Save name'));
    await tester.pump();
    expect(find.text('Enter your name.'), findsOneWidget);
  });

  testWidgets('rejects short and mismatched passwords before saving', (
    tester,
  ) async {
    await openProfile(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), 'abc');
    await tester.enterText(fields.at(3), 'different');
    final button = find.widgetWithText(FilledButton, 'Change password');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Use at least 6 characters.'), findsOneWidget);
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });
}
