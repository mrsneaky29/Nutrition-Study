import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';
import '../local_sync/http_local_record_sync_client.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    this.onSignIn,
    this.showLocalSetup = false,
    this.requireHttps = false,
    this.initialCollectorNumber = '',
    this.initialServerUrl = '',
    this.initialAccessKey = '',
    super.key,
  });

  final ValueChanged<CollectorAccessInput>? onSignIn;
  final bool showLocalSetup;
  final bool requireHttps;
  final String initialCollectorNumber;
  final String initialServerUrl;
  final String initialAccessKey;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class CollectorAccessInput {
  const CollectorAccessInput({
    required this.collectorCode,
    this.serverUrl = '',
    this.accessKey = '',
  });

  final String collectorCode;
  final String serverUrl;
  final String accessKey;
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _collectorCode = TextEditingController();
  final _serverUrl = TextEditingController();
  final _accessKey = TextEditingController();

  @override
  void initState() {
    super.initState();
    _collectorCode.text = widget.initialCollectorNumber;
    _serverUrl.text = widget.initialServerUrl;
    _accessKey.text = widget.initialAccessKey;
  }

  @override
  void dispose() {
    _collectorCode.dispose();
    _serverUrl.dispose();
    _accessKey.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final number = int.parse(_collectorCode.text.trim());
      widget.onSignIn?.call(
        CollectorAccessInput(
          collectorCode: 'C${number.toString().padLeft(3, '0')}',
          serverUrl: _serverUrl.text.trim(),
          accessKey: _accessKey.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ResponsivePage(
    child: SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.health_and_safety_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.showLocalSetup
                          ? 'Enter your collector number and access details. Before switching phones, sync any pending visits on the old phone. Signing in here ends its session for this number.'
                          : 'Enter the collector number created by the administrator. '
                                'The first phone to use it becomes the assigned phone.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _collectorCode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Collector number',
                        hintText: '1',
                      ),
                      validator: (value) =>
                          !RegExp(r'^[1-9]\d*$').hasMatch(value?.trim() ?? '')
                          ? 'Enter a number such as 1.'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (widget.showLocalSetup) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _serverUrl,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: widget.requireHttps
                              ? 'Server address'
                              : 'Home server address',
                          hintText: widget.requireHttps
                              ? 'https://server.example.com'
                              : 'http://192.168.1.5:8787',
                        ),
                        validator: (value) {
                          return !HttpLocalRecordSyncClient.isValidApiBaseUrl(
                                value ?? '',
                                requireHttps: widget.requireHttps,
                              )
                              ? 'Enter the server address provided by the administrator.'
                              : null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _accessKey,
                        obscureText: true,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Collector access key',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 16
                            ? 'Enter your collector access key.'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submit,
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
