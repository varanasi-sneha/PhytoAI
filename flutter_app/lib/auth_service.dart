import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  User? get currentUser => _supabase.auth.currentUser;

  /// Sign up and create a minimal profile row so newly created accounts
  /// immediately have profile data available to the app.
  Future<AuthResponse> signUp(String email, String password, String firstName, String lastName) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'full_name': '$firstName $lastName',
      },
    );

    // Ensure a profiles row exists so the profile screen has consistent data.
    try {
      final user = response.user;
      if (user != null) {
        await _supabase.from('profiles').upsert({
          'id': user.id,
          'name': '$firstName $lastName',
          'email': user.email,
          'first_name': firstName,
          'last_name': lastName,
        }, onConflict: 'id');
      }
    } catch (_) {
      // best-effort upsert failed; ignore silently in production.
    }

    return response;
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    return response;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  String? getAccessToken() {
    return _supabase.auth.currentSession?.accessToken;
  }
}