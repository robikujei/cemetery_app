import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final supabase = ref.read(supabaseProvider);
  return AuthNotifier(supabase);
});

class AuthState {
  final User? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState({this.user, this.isLoading = false, this.errorMessage});

  AuthState copyWith({User? user, bool? isLoading, String? errorMessage}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final SupabaseClient _supabase;

  AuthNotifier(this._supabase) : super(AuthState()) {
    // Check if user is already logged in
    _supabase.auth.onAuthStateChange.listen((event) {
      state = state.copyWith(user: event.session?.user);
    });
    state = state.copyWith(user: _supabase.auth.currentUser);
  }

  // Login with email and password
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      state = state.copyWith(user: response.user, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  // Register new user
  Future<bool> register(String email, String password, String name, String role) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    
    try {
      // Create user in Supabase Auth
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'role': role,
        },
      );
      
      if (response.user != null) {
        // Insert user details into your users table
        await _supabase.from('users').insert({
          'name': name,
          'email': email,
          'password': 'auth_managed', // Supabase Auth handles password
          'role': role,
        });
        
        state = state.copyWith(user: response.user, isLoading: false);
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    await _supabase.auth.signOut();
    state = AuthState();
  }
}