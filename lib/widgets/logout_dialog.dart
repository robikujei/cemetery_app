import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/session_providers.dart';
import '../providers/visitor_nav_providers.dart';
import '../services/audit_service.dart';
import '../services/logout_service.dart';

Future<void> showLogoutDialog(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final completed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _LogoutDialog(),
  );
  if (completed != true) return;
  container.read(sessionProvider.notifier).state = null;
  container.read(visitorNavIndexProvider.notifier).state = 0;
  if (context.mounted) context.go('/login');
}

class _LogoutDialog extends StatefulWidget {
  const _LogoutDialog();

  @override
  State<_LogoutDialog> createState() => _LogoutDialogState();
}

class _LogoutDialogState extends State<_LogoutDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _logout() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      await endSession(
        recordAudit: () =>
            AuditService.log(action: 'LOGOUT', entityType: 'session'),
        signOut: () => client.auth.signOut(scope: SignOutScope.local),
        hasSession: () => client.auth.currentSession != null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not finish logging out. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Logout'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_busy ? 'Logging out?' : 'Are you sure you want to logout?'),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _logout,
          child: Text(_busy ? 'Logging out?' : 'Logout'),
        ),
      ],
    ),
  );
}
