import 'package:pro_tocol/model/entities/Profile.dart';
import 'package:pro_tocol/model/services/AuthService.dart';

class ProfileRepository {
  final AuthService _authService;

  ProfileRepository(this._authService);

  Future<Profile> signUp({
    required String email,
    required String password,
    required String profileName,
  }) async {
    return await _authService.signUp(
      email: email,
      password: password,
      profileName: profileName,
    );
  }

  Future<Profile> signIn({
    required String email,
    required String password,
  }) async {
    return await _authService.signIn(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }

  Future<Profile?> getCurrentProfile() async {
    return await _authService.getCurrentProfile();
  }

  bool get isLoggedIn => _authService.isLoggedIn;

  Stream<dynamic> get onAuthStateChange => _authService.onAuthStateChange;
}