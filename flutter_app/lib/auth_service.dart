import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  User? get currentUser => _supabase.auth.currentUser;

  Future<AuthResponse> signUp(String email, String password, String firstName, String lastName) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'full_name': '$firstName $lastName',
      },
    );
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final session = _supabase.auth.currentSession;

    print("ACCESS TOKEN:");
    print(session?.accessToken);

    return response;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  String? getAccessToken() {
    return _supabase.auth.currentSession?.accessToken;
  }
}