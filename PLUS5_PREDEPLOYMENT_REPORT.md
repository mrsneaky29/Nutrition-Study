# Nutrition Study 1.0.0+5 pre-deployment checkpoint

This is a synthetic-data test kit, not an approved live survey deployment. Existing +2/+3/+4 kits remain unchanged. The public information website is an idea only and has not been implemented.

## Verified

- Integrated +5 collector HTTPS enforcement and separate administrator web build.
- Integrated Antigravity backend commits 347b1b8 and 7966a3a.
- Final integrated regression suite: 244 passed, 12 skipped, including collector-number 100 and 1000 compatibility checks.
- Static analysis: no issues. Web packaging tests: 24 passed.
- On Ubuntu 24.04.4 VPS: synthetic authentication/submission/admin retrieval/restart-persistence smoke test passed.
- On Ubuntu: all five release-lifecycle tests and 35 backup/restore assertions passed. Lifecycle uses mock systemctl; restore failure injection uses a mock. These do not prove production backup automation or offsite recovery.
- Real systemd test: DynamicUser non-root execution, ProtectSystem/ProtectHome/PrivateTmp sandbox, HTTPS-proxy header rejection, synthetic writes and record persistence after real service restart passed.
- Corrected service startup to direct `/usr/bin/dart <server.dart>`: the standalone backend imports only Dart standard libraries. `dart run` otherwise attempts to resolve the Flutter project's SDK dependencies. Retested direct execution with Flutter pubspec present under the read-only sandbox.
- Caddy configuration validated on installed Caddy 2.11.4. Real systemd unit validation and host preflight passed.
- Removed the inconsistent 99-collector limit in app login/provisioning, participant ID formatting, and backend prefix validation. No artificial participant count cap was added.
- Final signed APK 1.0.0+5 verified: expected application ID and release certificate, manifest does not explicitly enable cleartext. APK SHA256: `1859d3afa4cef1da09987b443b9c107f20de7560cb0adc0ac05538c7f46c2982`.
- Ubuntu service layout and `plus5-vps` account are prepared. Study service is inactive; Caddy's default website is stopped. No study routes or public backend listener have been enabled.

## Kit contents

- Signed shared APK, version 1.0.0+5, public HTTPS mode. Collectors enter the server URL and their own credentials at sign-in. No real domain is embedded yet.
- Source archive from the committed integration checkout, excluding untracked files by using Git archive.
- Admin web archive compiled against `https://api.example.org` solely for build verification. **Rebuild it with the actual API domain before deployment.**
- Deployment scripts and this report are included in source. Secrets and live data are not included.

## Required before survey deployment

1. Purchase the domain, create API/admin A records, and verify DNS.
2. Rebuild administrator assets with the real HTTPS API origin and package a reviewed server release.
3. Generate actual private collector/admin credentials; configure exact CORS origins. Never publish credentials in Drive release folders.
4. Apply reviewed firewall rules: preserve SSH, allow HTTPS/HTTP, do not expose backend port 8787.
5. Start the real installed service and Caddy using the real domain, verify TLS certificates and admin access.
6. Test one or more actual phones over mobile data: submit, retry after disconnection, confirm no duplicate, switch login, and observe administrator updates.
7. Configure scheduled backup and choose a separate secure offsite destination. Verify restore of a current synthetic deployment backup before participant use.
8. Verify final APK signature/version/hash, then distribute; no Play Store publication is planned.

Linux synthetic test state retained under separately named `nutrition-v5-test-*` state directories is not production data. Transient test services were stopped afterward. SSH private keys and Android signing keys stay out of all release archives.
