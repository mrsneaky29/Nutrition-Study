import 'package:flutter/material.dart';

import 'admin/admin_app.dart';
import 'admin/local_api_visit_repository.dart';
import 'domain/authenticated_user.dart';

/// Browser-only entrypoint; it is deliberately separate from `main.dart`.
void main() => runApp(const _AdminEntryApp());

class _AdminEntryApp extends StatefulWidget {
  const _AdminEntryApp();

  @override
  State<_AdminEntryApp> createState() => _AdminEntryAppState();
}

class _AdminEntryAppState extends State<_AdminEntryApp> {
  static const _admin = AuthenticatedUser(
    id: 'admin.local',
    role: UserRole.admin,
  );
  final _keyController = TextEditingController();
  LocalApiVisitRepository? _repository;
  String? _error;
  bool _connecting = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting) return;
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter the administrator access key.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final repository = LocalApiVisitRepository(apiKey: key);
    try {
      await repository.listVisibleTo(_admin);
      if (!mounted) {
        repository.close();
        return;
      }
      _keyController.clear();
      setState(() => _repository = repository);
    } catch (error) {
      repository.close();
      if (mounted) {
        setState(
          () => _error = error is LocalApiException ? error.message : 'The server returned data this console cannot safely open. Contact the study administrator.',
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    if (repository != null) {
      return AdminPortalApp(
        repository: repository,
        admin: _admin,
        collectorGateway: repository,
        onSignOut: () {
          repository.close();
          _keyController.clear();
          setState(() {
            _repository = null;
            _error = null;
          });
        },
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vivayu',
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'web/icons/Vivayu-192.png',
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          semanticLabel: 'Vivayu logo',
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Vivayu',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Administrator sign in'),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the administrator key for the study server.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _keyController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Administrator access key',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _connecting ? null : _connect,
                    child: Text(
                      _connecting ? 'Connecting…' : 'Open admin page',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
