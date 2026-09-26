import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';
import '../local_sync/http_local_record_sync_client.dart';
import '../collector_auth/collector_qr_scanner_contract.dart';
import '../collector_auth/mobile_collector_qr_scanner.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    this.onSignIn,
    this.showLocalSetup = false,
    this.requireHttps = false,
    this.initialCollectorNumber = '',
    this.initialServerUrl = '',
    this.initialAccessKey = '',
    this.scanner,
    super.key,
  });

  final ValueChanged<CollectorAccessInput>? onSignIn;
  final bool showLocalSetup;
  final bool requireHttps;
  final String initialCollectorNumber;
  final String initialServerUrl;
  final String initialAccessKey;
  final CollectorQrScannerContract? scanner;

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
  String? _scanMessage;
  bool _isScanning = false;

  bool get _qrOnlyProduction => widget.showLocalSetup && widget.requireHttps;

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

  Future<void> _scanQr() async {
    if (_isScanning) return;

    final serverUrl = widget.initialServerUrl.trim();
    if (!HttpLocalRecordSyncClient.isValidApiBaseUrl(
      serverUrl,
      requireHttps: true,
    )) {
      setState(() {
        _scanMessage = 'Sign-in is not configured. Contact your administrator.';
      });
      return;
    }

    setState(() {
      _scanMessage = null;
      _isScanning = true;
    });

    try {
      final result = await (widget.scanner ?? MobileCollectorQrScanner(context))
          .scanCode(expectedServerUrl: serverUrl, requireHttps: true);
      if (!mounted) return;
      switch (result) {
        case QrScannerSuccess(:final payload):
          final resolvedServer = payload.resolveServerUrl(serverUrl);
          if (!HttpLocalRecordSyncClient.isValidApiBaseUrl(
            resolvedServer,
            requireHttps: true,
          ) ||
              (payload.serverUrl != null &&
                  !_sameServer(payload.serverUrl!, serverUrl))) {
            setState(() {
              _scanMessage = 'The QR code is invalid. Ask your administrator for a new one.';
            });
            return;
          }
          widget.onSignIn?.call(
            CollectorAccessInput(
              collectorCode: payload.collectorCode,
              serverUrl: resolvedServer,
              accessKey: payload.collectorKey,
            ),
          );
        case QrScannerCancelled():
          setState(() => _scanMessage = 'QR sign-in was cancelled. Scan your setup QR code to continue.');
        case QrScannerPermissionDenied():
          setState(() => _scanMessage = 'Camera access is needed to scan your setup QR code. Allow camera access in app settings.');
        case QrScannerInvalid():
          setState(() => _scanMessage = 'The QR code is invalid. Ask your administrator for a new one.');
        case QrScannerError():
          setState(() => _scanMessage = 'The camera is unavailable. Check camera access and try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _scanMessage = 'The camera is unavailable. Check camera access and try again.');
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  bool _sameServer(String first, String second) {
    Uri? uri(String value) => Uri.tryParse(
      value.trim().replaceFirst(RegExp(r'/+$'), ''),
    );
    final left = uri(first);
    final right = uri(second);
    if (left == null || right == null) return false;
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.port == right.port &&
        left.path == right.path;
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
                      _qrOnlyProduction
                          ? 'Scan the collector setup QR code provided by your administrator to sign in.'
                          : widget.showLocalSetup
                          ? 'Enter your collector number and access details. Before switching phones, sync any pending visits on the old phone. Signing in here ends its session for this number.'
                          : 'Enter the collector number created by the administrator. '
                                'The first phone to use it becomes the assigned phone.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (!_qrOnlyProduction) TextFormField(
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
                    if (widget.showLocalSetup && !_qrOnlyProduction) ...[
                      const SizedBox(height: 16),
                      if (!(widget.requireHttps &&
                          widget.initialServerUrl.isNotEmpty))
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
                    if (_qrOnlyProduction) ...[
                      FilledButton.icon(
                        onPressed: _isScanning ? null : _scanQr,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.qr_code_scanner),
                        label: Text(_isScanning ? 'Scanning…' : 'Scan sign-in QR'),
                      ),
                      if (_scanMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _scanMessage!,
                          key: const Key('qr-sign-in-message'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    if (!_qrOnlyProduction) FilledButton(
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
