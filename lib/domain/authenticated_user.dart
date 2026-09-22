enum UserRole { collector, admin }

/// Identity supplied by the authentication layer; no Firebase dependency here.
class AuthenticatedUser {
  const AuthenticatedUser({required this.id, required this.role})
    : assert(id != '');

  final String id;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin;
  bool get isCollector => role == UserRole.collector;
}
