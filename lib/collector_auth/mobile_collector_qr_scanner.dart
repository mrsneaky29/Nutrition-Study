import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'collector_qr_payload.dart';
import 'collector_qr_scanner_contract.dart';

/// Camera-backed implementation of [CollectorQrScannerContract].
///
/// Raw QR contents are only passed to the payload parser. They are never
/// displayed or logged by this scanner.
class MobileCollectorQrScanner implements CollectorQrScannerContract {
  MobileCollectorQrScanner(this.context);

  final BuildContext context;

  @override
  Future<QrScannerResult> scanCode({
    String? expectedServerUrl,
    bool requireHttps = true,
  }) async {
    final result = await Navigator.of(context).push<QrScannerResult>(
      MaterialPageRoute<QrScannerResult>(
        fullscreenDialog: true,
        builder: (routeContext) => _CollectorQrScannerPage(
          expectedServerUrl: expectedServerUrl,
          requireHttps: requireHttps,
        ),
      ),
    );
    return result ?? const QrScannerCancelled();
  }
}

class _CollectorQrScannerPage extends StatefulWidget {
  const _CollectorQrScannerPage({
    required this.expectedServerUrl,
    required this.requireHttps,
  });

  final String? expectedServerUrl;
  final bool requireHttps;

  @override
  State<_CollectorQrScannerPage> createState() =>
      _CollectorQrScannerPageState();
}

class _CollectorQrScannerPageState extends State<_CollectorQrScannerPage>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _handlingDetection = false;
  bool _isClosed = false;
  String? _invalidMessage;
  String? _cameraMessage;
  bool _permissionDenied = false;
  bool _cameraErrorReported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      // The route has its own one-result guard. Normal mode lets the user retry
      // the same invalid code after dismissing the error state.
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    _isClosed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isClosed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (_controller.value.hasCameraPermission && _invalidMessage == null) {
          unawaited(_resumeCamera());
        }
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_stopCamera());
        break;
    }
  }

  Future<void> _resumeCamera() async {
    try {
      await _controller.start();
    } on MobileScannerException catch (error) {
      _showCameraError(error);
    } on Object {
      if (mounted && !_isClosed) {
        setState(() {
          _cameraMessage = 'The camera is unavailable. Please try again.';
        });
      }
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _controller.stop();
    } on Object {
      // Ignore stop races while the camera is initializing or the route closes.
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handlingDetection || _isClosed || _invalidMessage != null) return;

    String? rawValue;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        rawValue = barcode.rawValue;
        break;
      }
    }
    if (rawValue == null) return;

    _handlingDetection = true;
    try {
      final payload = CollectorQrPayload.parse(
        rawValue,
        expectedServerUrl: widget.expectedServerUrl,
        requireHttps: widget.requireHttps,
      );
      if (!_isClosed && mounted) {
        Navigator.of(context).pop<QrScannerResult>(QrScannerSuccess(payload));
      }
    } on QrPayloadException {
      _showInvalidCode();
    } catch (_) {
      // Do not put QR contents or parser details into a UI error message.
      _showInvalidCode();
    }
  }

  void _showInvalidCode() {
    if (_isClosed || !mounted) return;
    setState(() {
      _invalidMessage =
          'This QR code could not be validated as a collector setup code.';
    });
    _pauseCamera();
  }

  Future<void> _pauseCamera() async {
    try {
      await _controller.pause();
    } on Object {
      // The route may be closing while the camera is stopping.
    }
  }

  Future<void> _retry() async {
    if (_isClosed) return;
    setState(() {
      _handlingDetection = false;
      _invalidMessage = null;
      _cameraMessage = null;
      _permissionDenied = false;
      _cameraErrorReported = false;
    });
    try {
      await _controller.start();
    } on MobileScannerException catch (error) {
      _showCameraError(error);
    } on Object {
      if (!mounted || _isClosed) return;
      setState(() {
        _cameraMessage = 'The camera is unavailable. Please try again.';
      });
    }
  }

  void _showCameraError(MobileScannerException error) {
    if (!mounted || _isClosed) return;
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final message = permissionDenied
        ? 'Camera access is needed to scan a setup code. Allow camera access in your device settings, then try again.'
        : 'The camera is unavailable. Please try again.';
    if (_permissionDenied == permissionDenied && _cameraMessage == message) {
      return;
    }
    setState(() {
      _permissionDenied = permissionDenied;
      _cameraMessage = message;
    });
  }

  void _onCameraError(MobileScannerException error) {
    if (_cameraErrorReported || _isClosed) return;
    _cameraErrorReported = true;
    // errorBuilder may run during build; defer the state update until afterward.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showCameraError(error);
    });
  }

  void _finishWithPermissionResult() {
    Navigator.of(context)
        .pop<QrScannerResult>(const QrScannerPermissionDenied());
  }

  void _finishWithCameraError() {
    Navigator.of(
      context,
    ).pop<QrScannerResult>(const QrScannerError(error: 'Camera unavailable'));
  }

  void _cancel() {
    if (_isClosed) return;
    _isClosed = true;
    Navigator.of(context).pop<QrScannerResult>(const QrScannerCancelled());
  }

  @override
  Widget build(BuildContext context) {
    final message = _invalidMessage ?? _cameraMessage;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan collector setup code'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        leading: IconButton(
          tooltip: 'Cancel scan',
          icon: const Icon(Icons.close),
          onPressed: _cancel,
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            useAppLifecycleState: false,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              _onCameraError(error);
              return const ColoredBox(color: Colors.black);
            },
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          if (message != null)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.86),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          _permissionDenied
                              ? Icons.no_photography_outlined
                              : Icons.qr_code_2,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_permissionDenied) ...<Widget>[
                          FilledButton(
                            onPressed: _retry,
                            child: const Text('Try again'),
                          ),
                          TextButton(
                            onPressed: _finishWithPermissionResult,
                            child: const Text('Close scanner'),
                          ),
                        ] else ...<Widget>[
                          FilledButton(
                            onPressed: _retry,
                            child: const Text('Scan again'),
                          ),
                          TextButton(
                            onPressed: _finishWithCameraError,
                            child: const Text('Close scanner'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            const Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: Text(
                'Place the collector setup QR code inside the frame.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }
}
