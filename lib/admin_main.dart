import 'package:flutter/widgets.dart';

import 'admin/admin_app.dart';
import 'admin/local_api_visit_repository.dart';
import 'domain/authenticated_user.dart';

/// Browser-only entrypoint; it is deliberately separate from `main.dart`.
void main() {
  runApp(
    AdminPortalApp(
      repository: LocalApiVisitRepository(),
      admin: const AuthenticatedUser(id: 'admin.demo', role: UserRole.admin),
    ),
  );
}
