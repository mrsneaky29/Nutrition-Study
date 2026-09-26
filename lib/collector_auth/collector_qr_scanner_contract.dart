import 'collector_qr_payload.dart';

/// Reasons why a QR code scan may not produce valid setup credentials.
enum QrScanFailureReason {
  /// User declined the camera permission request.
  cameraPermissionDenied,

  /// Camera permission was permanently denied; settings navigation is required.
  cameraPermissionPermanentlyDenied,

  /// User cancelled or closed the camera scanner view.
  cancelled,

  /// The scanned code is not a valid Study Collector setup code.
  invalidQr,

  /// Camera hardware or sensor could not be accessed.
  hardwareUnavailable,
}

/// Result from a QR code scanning attempt.
sealed class QrScannerResult {
  const QrScannerResult();
}

/// The QR code was successfully scanned and parsed into valid credentials.
class QrScannerSuccess extends QrScannerResult {
  const QrScannerSuccess(this.payload);

  final CollectorQrPayload payload;
}

/// The user dismissed or cancelled the scanner.
class QrScannerCancelled extends QrScannerResult {
  const QrScannerCancelled();
}

/// Camera permission was denied by the user.
class QrScannerPermissionDenied extends QrScannerResult {
  const QrScannerPermissionDenied({
    this.isPermanentlyDenied = false,
    this.message =
        'Camera permission is required to scan the collector setup QR code. '
        'Please grant camera access in app settings.',
  });

  final bool isPermanentlyDenied;
  final String message;
}

/// The scanned code was unreadable or failed payload validation.
class QrScannerInvalid extends QrScannerResult {
  const QrScannerInvalid({
    required this.reason,
    this.message = 'The scanned QR code is not a valid Study Collector setup code.',
  });

  final String reason;
  final String message;
}

/// An unexpected camera or device error occurred.
class QrScannerError extends QrScannerResult {
  const QrScannerError({
    required this.error,
    this.message = 'Camera scanner error. Please try again.',
  });

  final Object error;
  final String message;
}

/// Abstract contract for a QR scanner implementation.
///
/// Decouples UI and authentication logic from the underlying camera plugin,
/// enabling headless automated testing, simulated scans, and clean platform bindings.
abstract interface class CollectorQrScannerContract {
  /// Initiates a camera scan session and returns the resulting [QrScannerResult].
  Future<QrScannerResult> scanCode({
    String? expectedServerUrl,
    bool requireHttps = true,
  });
}
