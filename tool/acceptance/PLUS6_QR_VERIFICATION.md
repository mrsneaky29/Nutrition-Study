# 1.0.0+6 mandatory QR sign-in

Production collector builds use LOCAL_GENERIC_RELEASE=true,
LOCAL_PUBLIC_RELEASE=true and the configured HTTPS API origin.
First-time login exposes only Scan sign-in QR: no collector-number, server,
key fields or manual Continue bypass. QR validation supplies the collector
identity/key to the existing server session bootstrap and secure storage.
Routine reopening restores the saved session; session rejection returns to QR
login without deleting stored survey records. A QR is private per collector,
not bound to a phone.

## Implemented and automated verification

- Camera scans QR codes only, with one-result guarding and explicit camera
  lifecycle pause/resume/disposal.
- Denied permission, unavailable camera, cancellation and invalid QR show
  generic actionable messages without authentication bypass.
- Parsing enforces version/type, collector identity, bounded printable keys,
  a 4096-character input bound and configured-server matching.
- Malformed JSON/URI errors no longer include raw parser exception snippets.
- QR/auth/login suite: 35 tests passed.
- Public HTTPS saved-session restoration: 1 test passed.
- Existing generic local-session and collector-client suites: 14 tests passed.
- Static analysis: no issues.
- Android phones request portrait orientation.

## Build prerequisites and safeguards

Run flutter pub get before release compilation. Android generated plugin
registration must include flutter_secure_storage and mobile_scanner.
On this Windows host, FLUTTER_WINDOWS=false for the pub-get command avoids
unneeded desktop symlink creation without changing global Flutter settings.
Never ship the test application ID as the production package. Existing +5
artifacts remain unchanged.

## Still requires physical acceptance

### Physical checks completed on Galaxy M14

The +6 separate test package was installed and versionCode=6 verified.
User confirmed real-camera Collector 1 QR sign-in succeeded. User then created
an offline synthetic record and reported automatic sync when mobile data was
enabled. Read-only public API verification confirmed one synthetic record on
the server. User swiped the app away and reopened it, then confirmed the record
still showed synced. These results do not prove two-phone takeover or permission
denial/settings recovery; those remain outstanding.

Camera permission grant/deny/settings recovery, invalid and valid QR scanning,
background/resume, portrait behaviour, reopen session restoration, mobile-data
offline sync/idempotency, and two-phone latest-login takeover. Automated fake
scanner UI tests do not prove that the camera plugin works on a real device.
No real participant collection until these checks pass.
