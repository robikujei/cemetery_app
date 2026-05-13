import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: 'Create an account',
                subtitle: 'This is a placeholder — wire to Supabase/Firebase next.',
              ),
              const SizedBox(height: 12),
              const AppCard(
                child: Text('Registration form goes here (name, email/phone, password).'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

