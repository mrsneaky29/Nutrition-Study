enum CollectorAccountStatus { active, disabled }

/// A server-created collector identity. It deliberately contains no password,
/// device token, or other credential that could be exposed in the portal UI.
class CollectorAccount {
  const CollectorAccount({
    required this.code,
    required this.status,
    required this.createdAt,
    this.displayName,
    this.deviceBinding,
  }) : assert(code != '');

  final String code;
  final String? displayName;
  final CollectorAccountStatus status;
  final DateTime createdAt;
  final CollectorDeviceBinding? deviceBinding;

  bool get isActive => status == CollectorAccountStatus.active;
  bool get isBound => deviceBinding != null;

  CollectorAccount copyWith({
    String? displayName,
    CollectorAccountStatus? status,
    CollectorDeviceBinding? deviceBinding,
    bool clearDeviceBinding = false,
  }) => CollectorAccount(
    code: code,
    displayName: displayName ?? this.displayName,
    status: status ?? this.status,
    createdAt: createdAt,
    deviceBinding: clearDeviceBinding
        ? null
        : deviceBinding ?? this.deviceBinding,
  );
}

/// A safe-to-display summary of the currently bound installation.
///
/// Fingerprints and issued credentials are intentionally not available here.
class CollectorDeviceBinding {
  const CollectorDeviceBinding({
    required this.label,
    required this.boundAt,
  }) : assert(label != '');

  final String label;
  final DateTime boundAt;
}
