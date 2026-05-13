import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audit_service.dart';
import '../../models/app_user.dart';
import '../../providers/session_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  
  // Error messages
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // Email validation function
  bool _isValidEmail(String email) {
    if (email.isEmpty) return false;
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  bool _validateForm() {
    bool isValid = true;
    
    // Validate email format
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email address');
      isValid = false;
    } else if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Please enter a valid email address');
      isValid = false;
    } else {
      setState(() => _emailError = null);
    }
    
    // Validate password
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _passwordError = 'Please enter your password');
      isValid = false;
    } else {
      setState(() => _passwordError = null);
    }
    
    return isValid;
  }

 Future<void> _signInWithSupabase() async {
  if (!_validateForm()) return;

  setState(() {
    _isLoading = true;
  });

  try {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: _emailCtrl.text.trim().toLowerCase(),
      password: _passwordCtrl.text,
    );

    if (response.user != null) {
      final userData = await Supabase.instance.client
          .from('users')
          .select('name, role')
          .eq('email', _emailCtrl.text.trim().toLowerCase())
          .single();
      
      // ✅ ADD AUDIT LOG FOR LOGIN
      await AuditService.log(
        action: 'LOGIN',
        entityType: 'user',
        entityId: response.user!.id,
        details: 'User ${userData['name']} (${userData['role']}) logged in',
      );
      
      final appUser = AppUser(
        id: response.user!.id,
        displayName: userData['name'] ?? _emailCtrl.text.trim().split('@').first,
        role: _mapRoleToEnum(userData['role']),
      );
      
      ref.read(sessionProvider.notifier).state = appUser;
      
      if (mounted) {
        _navigateByRole(userData['role']);
      }
    } else {
      _showErrorSnackBar('Invalid email or password. Please try again.');
    }
  } on AuthException catch (e) {
    _showErrorSnackBar(e.message);
  } catch (e) {
    _showErrorSnackBar('An error occurred. Please try again.');
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
  void _navigateByRole(String? role) {
    switch (role) {
      case 'admin':
        context.go('/admin');
        break;
      case 'gate_officer':
        context.go('/gate-officer');
        break;
      case 'lot_owner':
        context.go('/lot-owner');
        break;
      default:
        context.go('/visitor');
    }
  }

  UserRole _mapRoleToEnum(String? role) {
    switch (role) {
      case 'admin':
        return UserRole.admin;
      case 'gate_officer':
        return UserRole.gateOfficer;
      default:
        return UserRole.visitor;
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.church, size: 80, color: Colors.green),
                const SizedBox(height: 24),
                const Text(
                  'Eternal Rest',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                const SizedBox(height: 8),
                const Text('A quiet guide for your journey through memories.'),
                const SizedBox(height: 32),
                
                // Email Field with format validation
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email),
                    border: const OutlineInputBorder(),
                    errorText: _emailError,
                    hintText: 'name@example.com',
                  ),
                ),
                const SizedBox(height: 16),
                
                // Password Field
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: const OutlineInputBorder(),
                    errorText: _passwordError,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Sign In Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _signInWithSupabase,
                    child: _isLoading ? const CircularProgressIndicator() : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Create Account Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account?"),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('Create Account'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}