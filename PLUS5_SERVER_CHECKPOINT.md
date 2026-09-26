# +5 server checkpoint addendum

The pre-deployment source/APK checkpoint is commit `faef803`. The domain is not yet configured; do not treat the kit as live survey approval.

After that checkpoint, the Ubuntu host firewall was enabled with default deny incoming and allow outgoing. Only TCP 22, 80, and 443 are allowed inbound (IPv4/IPv6); backend port 8787 is not opened. A fresh SSH connection and active SSH service were verified after activation.

The study backend and Caddy remain stopped; no real survey data is being served. Test services are stopped. Synthetic state is retained in separately named test directories, not production storage.

Automated offsite backups still need the owner's destination choice and setup. Backup/restore synthetic checks passed, but they do not replace an actual scheduled/offsite restore drill. HTTPS certificates, actual admin deployment, and mobile-data phone-to-admin testing await the real domain.

No signing keys, SSH keys, passphrases, API credentials, or participant records are in the Drive test kit. Existing +2/+3/+4 folders were not changed.
