import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user.dart';
import '../../providers/session_providers.dart';
import '../../services/audit_service.dart';
import '../../widgets/theme_mode_switch_tile.dart';

class AdminProfileScreen extends ConsumerStatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  ConsumerState<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends ConsumerState<AdminProfileScreen> {
  final _nameForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(sessionProvider)?.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save({required bool password}) async {
    final form = password ? _passwordForm : _nameForm;
    if (_busy || !form.currentState!.validate()) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    final session = ref.read(sessionProvider);
    if (user == null || session == null || session.role != UserRole.admin) {
      _message('Please sign in as an administrator again.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (password) {
        await client.auth.updateUser(UserAttributes(password: _password.text));
      } else {
        final email = user.email;
        if (email == null) throw StateError('Account email is unavailable');
        final updated = await client
            .from('users')
            .update({'name': _name.text.trim()})
            .eq('email', email)
            .select('name')
            .single();
        if (!mounted) return;
        ref.read(sessionProvider.notifier).state = AppUser(
          id: session.id,
          displayName: updated['name'] as String,
          role: session.role,
        );
      }
      await AuditService.log(
        action: 'UPDATE',
        entityType: 'user',
        entityId: user.id,
        details: password
            ? 'Administrator changed their password'
            : 'Administrator updated their display name',
      );
      if (!mounted) return;
      if (password) {
        _password.clear();
        _confirmation.clear();
        _passwordForm.currentState?.reset();
      }
      _message(password ? 'Password changed.' : 'Name updated.');
    } on AuthException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('Unable to save changes. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _card(
                  'Account details',
                  Form(
                    key: _nameForm,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your name.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: email,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Account email',
                            helperText: 'Your sign-in email (read-only)',
                            suffixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _save(password: false),
                          child: const Text('Save name'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _card(
                  'Change password',
                  Form(
                    key: _passwordForm,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'New password',
                            helperText: 'At least 6 characters',
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.length < 6
                              ? 'Use at least 6 characters.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmation,
                          enabled: !_busy,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Confirm your new password.'
                              : value != _password.text
                              ? 'Passwords do not match.'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _busy ? null : () => _save(password: true),
                          child: const Text('Change password'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _card('Appearance', const ThemeModeSwitchTile()),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(String title, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
