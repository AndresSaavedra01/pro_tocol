class Profile {
  final String id; // UID de Supabase Auth
  late final String profileName;
  final String email;

  Profile({
    required this.id,
    required this.profileName,
    required this.email,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      profileName: json['profile_name'] as String,
      email: json['email'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile_name': profileName,
      'email': email,
    };
  }
}
