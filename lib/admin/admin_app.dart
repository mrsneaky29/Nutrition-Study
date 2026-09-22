import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/visit_repository.dart';
import '../domain/authenticated_user.dart';
import 'access/admin_session_gateway.dart';
import 'admin_dashboard.dart';
import 'collectors/collector_account_gateway.dart';
import 'collectors/collector_management_page.dart';
import 'collectors/in_memory_collector_account_gateway.dart';

/// The standalone administration application.
///
/// Start this entrypoint in a browser with:
/// `flutter run -d chrome -t lib/admin_main.dart`
class AdminPortalApp extends StatelessWidget {
  AdminPortalApp({
    required this.repository,
    required this.admin,
    AdminSessionGateway? sessionGateway,
    CollectorAccountGateway? collectorGateway,
    super.key,
  }) : assert(admin.role == UserRole.admin),
       sessionGateway = sessionGateway ?? InMemoryAdminSessionGateway(admin),
       collectorGateway = collectorGateway ?? InMemoryCollectorAccountGateway();

  final VisitRepository repository;
  final AuthenticatedUser admin;
  final AdminSessionGateway sessionGateway;
  final CollectorAccountGateway collectorGateway;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1A2433);
    const canvas = Color(0xFFF4F7FB);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2855D9),
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Study Admin',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: canvas,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE4E9F2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7DFEC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7DFEC)),
          ),
        ),
      ),
      home: kIsWeb
          ? AdminPortalShell(
              repository: repository,
              admin: admin,
              sessionGateway: sessionGateway,
              collectorGateway: collectorGateway,
            )
          : const _WebOnlyNotice(),
    );
  }
}

/// Top-level navigation for the separate browser administration portal.
///
/// The collector app never imports or exposes this shell.
class AdminPortalShell extends StatefulWidget {
  const AdminPortalShell({
    required this.repository,
    required this.admin,
    required this.sessionGateway,
    required this.collectorGateway,
    super.key,
  });

  final VisitRepository repository;
  final AuthenticatedUser admin;
  final AdminSessionGateway sessionGateway;
  final CollectorAccountGateway collectorGateway;

  @override
  State<AdminPortalShell> createState() => _AdminPortalShellState();
}

class _AdminPortalShellState extends State<AdminPortalShell> {
  int _section = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Study Admin'),
          actions: compact
              ? null
              : [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.assignment_outlined),
                          label: Text('Visit records'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.badge_outlined),
                          label: Text('Collector access'),
                        ),
                      ],
                      selected: {_section},
                      onSelectionChanged: (value) {
                        setState(() => _section = value.single);
                      },
                    ),
                  ),
                ],
        ),
        body: IndexedStack(
          index: _section,
          children: [
            AdminDashboard(repository: widget.repository, admin: widget.admin),
            CollectorManagementPage(
              sessionGateway: widget.sessionGateway,
              collectorGateway: widget.collectorGateway,
            ),
          ],
        ),
        bottomNavigationBar: compact
            ? NavigationBar(
                selectedIndex: _section,
                onDestinationSelected: (value) {
                  setState(() => _section = value);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.assignment_outlined),
                    label: 'Visit records',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.badge_outlined),
                    label: 'Collector access',
                  ),
                ],
              )
            : null,
      );
    },
  );
}

class _WebOnlyNotice extends StatelessWidget {
  const _WebOnlyNotice();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The administration portal is available in a web browser only.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
