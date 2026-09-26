# +5 ownership and integration checkpoint

Antigravity owns `tool/local_sync_server.dart`, backend tests, and `tool/vps/` in a separate working folder and branch. Codex owns collector HTTPS wiring, Android packaging, admin web build configuration, and integration verification. Do not edit the other owner's files; report issues and integrate reviewed commits later. Existing +2/+3/+4 release folders remain frozen.

## Backend findings for Antigravity

- Credential generation permits `C1000` and higher, but public backend validation accepts only two or three digits. Align validation with the app/generator, without imposing a participant cap.
- Authentication throttling uses the peer socket address. Behind Caddy this is loopback for every request, so one caller can throttle everybody. Use a validated, trusted-proxy client-address strategy or another appropriately scoped mechanism. Never trust forwarded addresses from arbitrary direct peers.
- The configuration rejection test's matcher closure was corrected before this ownership handoff; the existing baseline is 240 passing tests and 12 skipped tests.

## Build commands after the real domain is chosen

```powershell
./tool/build_web_clients.ps1 -AdminOnly -PublicRelease -AdminApiBaseUrl https://api.YOUR-DOMAIN -NoPub
./tool/package_android_release.ps1 -BuildNumber 5 -PublicRelease -LocalApiBaseUrl https://api.YOUR-DOMAIN -SigningBackupConfirmed -NoPub
```

`-NoPub` is optional and assumes dependencies have already been resolved. The admin build never embeds the administrator key. The shared Android package rejects embedded collector identities/keys and requires HTTPS in public mode. The signing files must be restored locally from the existing private backup, never committed or added to a distribution kit.

Do not distribute a build using `api.example.org`: it is only a compile-check placeholder. Final signing, certificate/version checks, and real phone-to-HTTPS-to-admin verification remain required after domain and VPS setup. No live deployment has been performed.
