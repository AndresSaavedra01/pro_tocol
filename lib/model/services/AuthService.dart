import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pro_tocol/model/entities/Profile.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Stream of authentication state changes
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Check if the user is currently logged in
  bool get isLoggedIn => _client.auth.currentSession != null;

  /// Sign Up a new user and create their Profile in the Supabase database
  Future<Profile> signUp({
    required String email,
    required String password,
    required String profileName,
  }) async {
    final cleanEmail = email.trim();
    final cleanName = profileName.trim();

    if (cleanEmail.isEmpty || password.isEmpty || cleanName.isEmpty) {
      throw ArgumentError('Todos los campos son obligatorios.');
    }

    // 1. Sign up user in Supabase Auth
    final AuthResponse response = await _client.auth.signUp(
      email: cleanEmail,
      password: password,
      data: {'display_name': cleanName},
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Fallo al registrar el usuario en Supabase Auth.');
    }

    // 2. Insert into profiles table
    try {
      await _client.from('profiles').insert({
        'id': user.id,
        'profile_name': cleanName,
        'email': cleanEmail,
      });
    } catch (e) {
      // If insertion fails, we attempt to clean up or throw
      throw Exception('Error al guardar el perfil en la base de datos: $e');
    }

    return Profile(
      id: user.id,
      profileName: cleanName,
      email: cleanEmail,
    );
  }

  /// Sign In an existing user
  Future<Profile> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw ArgumentError('Email y contraseña son obligatorios.');
    }

    final AuthResponse response = await _client.auth.signInWithPassword(
      email: cleanEmail,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Credenciales inválidas.');
    }

    // Fetch the profile details from the profiles table
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      return Profile.fromJson(data);
    } catch (e) {
      // Return a fallback profile if not in profiles table
      return Profile(
        id: user.id,
        profileName: user.userMetadata?['display_name'] as String? ?? user.email ?? 'Usuario',
        email: user.email ?? '',
      );
    }
  }

  /// Sign Out the current user
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Get the current authenticated profile
  Future<Profile?> getCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      return Profile.fromJson(data);
    } catch (e) {
      return Profile(
        id: user.id,
        profileName: user.userMetadata?['display_name'] as String? ?? user.email ?? 'Usuario',
        email: user.email ?? '',
      );
    }
  }
}
