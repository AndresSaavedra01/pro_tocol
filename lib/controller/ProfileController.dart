import 'package:pro_tocol/model/entities/Profile.dart';
import 'package:pro_tocol/model/repositories/ProfileRepository.dart';

class ProfileController {
  final ProfileRepository _profileRepository;

  ProfileController(this._profileRepository);

  /// Sign up user
  Future<Profile> signUp({
    required String email,
    required String password,
    required String profileName,
  }) async {
    final cleanName = profileName.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('El nombre del perfil no puede estar vacío.');
    }
    if (cleanName.length < 3) {
      throw ArgumentError('El nombre del perfil debe tener al menos 3 caracteres.');
    }

    return await _profileRepository.signUp(
      email: email,
      password: password,
      profileName: cleanName,
    );
  }

  /// Sign in user
  Future<Profile> signIn({
    required String email,
    required String password,
  }) async {
    return await _profileRepository.signIn(
      email: email,
      password: password,
    );
  }

  /// Sign out user
  Future<void> signOut() async {
    await _profileRepository.signOut();
  }

  /// Get current user profile
  Future<Profile?> getCurrentProfile() async {
    return await _profileRepository.getCurrentProfile();
  }

  /// Check if user is logged in
  bool get isLoggedIn => _profileRepository.isLoggedIn;

  /// Get auth state change stream
  Stream<dynamic> get onAuthStateChange => _profileRepository.onAuthStateChange;
}