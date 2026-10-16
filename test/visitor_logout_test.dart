import 'dart:async';
import 'dart:convert';

import 'package:cemetery_app/providers/visitor_nav_providers.dart';
import 'package:cemetery_app/screens/visitor/visitor_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  var stallLogoutRequests = false;
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
      httpClient: MockClient((request) async {
        if (stallLogoutRequests && request.url.path.endsWith('/audit_log')) {
          return Completer<http.Response>().future;
        }
        if (stallLogoutRequests && request.url.path.endsWith('/logout')) {
          throw StateError('Network unavailable');
        }
        return http.Response(
          request.url.path.endsWith('/users')
              ? jsonEncode({
                  'name': 'Visitor',
                  'email': 'visitor@example.com',
                  'role': 'visitor',
                })
              : '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final height in [640.0, 480.0]) {
    testWidgets('visitor logout is reachable at height $height', (
      tester,
    ) async {
      stallLogoutRequests = height == 480;
      tester.view.physicalSize = Size(390, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await Supabase.instance.client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'test-token',
          'refresh_token': 'test-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'visitor-id',
            'aud': 'authenticated',
            'email': 'visitor@example.com',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-01-01T00:00:00Z',
          },
        }),
      );
      final router = GoRouter(
        initialLocation: '/visitor',
        routes: [
          GoRoute(
            path: '/visitor',
            builder: (_, _) => const VisitorShellScreen(),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('Login screen')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [visitorNavIndexProvider.overrideWith((ref) => 3)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final logout = find.widgetWithText(ElevatedButton, 'Logout from Account');
      await tester.scrollUntilVisible(logout, 150);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(logout).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(BottomNavigationBar)).top),
      );
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to logout?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(Supabase.instance.client.auth.currentSession, isNotNull);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Logout'));
      await tester.pumpAndSettle();
      expect(find.text('Login screen'), findsOneWidget);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
