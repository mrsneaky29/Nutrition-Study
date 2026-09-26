# +5 domain activation handoff

This checklist is for the existing Ubuntu VM, not a fresh install. Do not
regenerate its credentials, overwrite its state, or run the initial preparation
script again. Keep the historical +2, +3 and +4 test kits unchanged.

## Already verified before domain purchase

- The backend runs on loopback and is enabled at boot.
- The host firewall permits SSH and web ports, not direct backend access.
- A manually started encrypted offsite backup completed successfully.
- A separate synthetic encrypted Drive upload/download and isolated restore passed.
- The daily encrypted backup timer is enabled; its first scheduled run is still pending.

These checks do not establish public HTTPS or field-phone readiness. Antigravity
owns the current admin browser acceptance testing; review its final evidence
before marking those tests complete.

## After the domain is available

1. Choose distinct `api` and `admin` hostnames. Create their DNS A records for
   the VM's public IPv4. Add AAAA records only for configured, reachable IPv6.
2. Verify DNS resolution externally. Preserve SSH access throughout deployment.
3. Build the admin web release with the actual HTTPS API URL using
   `tool/build_web_clients.ps1`. Do not deploy the placeholder-domain test build
   or embed administrator credentials in web assets.
4. Package and import the reviewed backend, admin assets and VPS operations
   scripts together. In particular, retain `tool/vps/offsite-backup.sh` and
   `tool/vps/backup-state.sh`: the backup unit executes them through the current
   release link. Activate with the existing health-check/rollback workflow.
5. Set the exact HTTPS admin origin in the protected server environment file,
   retaining all existing credentials. Restart and verify private backend health.
6. Render and validate Caddy configuration for both real hostnames, then enable
   the public proxy. Verify trusted certificates, HTTP-to-HTTPS redirects,
   authenticated access and rejection of unauthenticated requests. Keep port
   8787 private.
7. Configure a collector phone with the HTTPS API URL. Use synthetic data on
   mobile data, not only home Wi-Fi: collect offline, reconnect, sync, confirm
   records in admin, and verify retries do not duplicate a submission.
8. Verify latest-login takeover across two phones, preservation of unsynced
   local records, and administrative access boundaries.
9. Review Antigravity's browser report for login, search/filter/detail views,
   missing-measurement reasons, BMI/BP calculations, edits, CSV exports, mobile
   layout and outage/loading behaviour. Record failures, not just screenshots.
10. Recheck backup success after release activation. Confirm the first scheduled
    backup when it runs; keep the recovery key separate and test restores only
    against isolated synthetic state. Agree on local and remote retention before
    real survey collection, without deleting existing backups implicitly.

## Go-live boundary

Do not describe +5 as survey-ready until public HTTPS, access controls, admin
acceptance, real-phone offline/sync checks and backup operations have passed.
The public information website remains an idea, not part of this deployment.

See [the operations manual](README.md) and
[encrypted backup setup](OFFSITE_BACKUP_SETUP.md) for procedures.
