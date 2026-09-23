# Off-Device Backup & Disaster Recovery Guide

This guide details the operational procedures for backing up, verifying, and restoring the home-PC Nutrition Study database using the official backup utility (`tool/backup_utility.ps1` and `tool/backup_utility.dart`).

---

## 1. Overview & Core Principles

The home-PC server maintains all synced study data in `.local_data/`:
- `.local_data/records.json`: Primary visit records store.
- `.local_data/conflicts.json`: Conflict inbox for rejected or ambiguous submissions.

The backup utility provides cryptographic SHA-256 verification, manifest generation, collision-safe naming, atomic operations, and overwrite safety snapshots.

### Single-Disk `.bak` vs. Off-Device Backups

> [!CAUTION]
> **A `.bak` file on the same computer is NOT an off-device backup.**
>
> The sync server automatically keeps `.local_data/records.json.bak` and `.local_data/conflicts.json.bak` as single previous snapshots to protect against process crashes or power interruptions during atomic file replacement.
>
> However, these `.bak` snapshots live on the **same physical storage drive**. A hardware drive failure, operating system crash, ransomware infection, power surge, theft, or flood will destroy both `records.json` and `records.json.bak` simultaneously.
>
> **Real off-device backups must physically leave the home PC.**

---

## 2. Choosing an Off-PC Destination

Always specify a backup target path located on physically separate storage:

| Target Type | Example Windows Path | Notes |
| :--- | :--- | :--- |
| **Dedicated USB Flash Drive** | `E:\StudyBackups` | Keep a dedicated flash drive labeled for study backups. Eject safely after use. |
| **External USB HDD / SSD** | `F:\StudyBackups` | Recommended for multi-week retention. Rotate two drives (Drive A / Drive B). |
| **Local Network Share (NAS)** | `\\Server\Backups\Study` | Ensure the share is restricted to authorized study personnel. |

The backup utility will create a timestamped folder inside your designated destination:
`backup_<yyyyMMdd_HHmmss>/` (e.g. `E:\StudyBackups\backup_20260923_180000`).

Existing backups are **never overwritten**. If two backups are run in the same second, an incrementing unique suffix is automatically appended.

---

## 3. Daily Backup Procedure (Post-Sync Window)

Run an off-device backup after every daily 2–3 hour sync window once field collectors have finished syncing.

### Step 1: Confirm Pending Uploads Reach Zero
Before creating a backup:
1. Open the Admin Portal (`lib/admin_main.dart`) or inspect collector devices.
2. Confirm all pending submissions have uploaded and the server's record count matches field visit logs.

### Step 2: Run the Backup Utility

Execute the PowerShell backup command:

```powershell
powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 `
  -Action Backup `
  -Destination "E:\StudyBackups"
```

To add an optional descriptive label:

```powershell
powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 `
  -Action Backup `
  -Destination "E:\StudyBackups" `
  -Label "evening_sync"
```

*(Direct Dart alternative: `dart run tool/backup_utility.dart backup --destination="E:\StudyBackups" --label="evening_sync"`)*

### Step 3: Verify the Backup Output
The utility creates the following structure in the destination directory:

```text
E:\StudyBackups\backup_20260923_180000\
├── records.json        # Synced participant visit records
├── conflicts.json      # Resolved and pending conflict records
├── manifest.json       # Metadata, record counts, file sizes, and SHA-256 hashes
└── SHA256SUMS          # Standard checksum file for external tool verification
```

The tool immediately computes and verifies SHA-256 hashes upon writing, outputting a summary:

```text
[BACKUP SUCCESS]
Backup Directory : E:\StudyBackups\backup_20260923_180000
Records File     : 142 records (SHA-256: 7f83b1...)
Conflicts File   : 3 conflicts (SHA-256: 2c6242...)
Manifest File    : SHA-256: 9e107d...
SHA256SUMS       : Written and verified.
```

---

## 4. Verifying a Backup

You can verify the cryptographic integrity of any backup at any time without modifying any data.

### Verification Command

```powershell
powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 `
  -Action Verify `
  -BackupPath "E:\StudyBackups\backup_20260923_180000"
```

*(Direct Dart alternative: `dart run tool/backup_utility.dart verify --backup="E:\StudyBackups\backup_20260923_180000"`)*

### What the Verification Checks
1. **Manifest Integrity**: Reads and parses `manifest.json`, verifying version and metadata.
2. **File Checksums**: Recalculates the SHA-256 hash of `records.json` and `conflicts.json` and compares them against the manifest.
3. **Format & Structure**: Validates that both JSON files parse cleanly and conform to expected list schemas.
4. **Checksum File**: Verifies consistency with `SHA256SUMS`.

If verification succeeds, the command exits with code `0`. If any byte has been tampered with or corrupted, it outputs `[VERIFICATION FAILED]` with details and exits with a non-zero code.

---

## 5. Safe Restore Procedures

### Scenario A: Restoring onto a Replacement PC (Clean Target)

Use this procedure if the original PC suffered total hardware failure, drive loss, or replacement:

1. Provision the replacement PC with Dart / Flutter and clone the study repository.
2. Attach the external backup drive (e.g. `E:`).
3. First, verify the chosen backup:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 `
     -Action Verify `
     -BackupPath "E:\StudyBackups\backup_20260923_180000"
   ```
4. Restore into the default `.local_data` directory:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 `
     -Action Restore `
     -BackupPath "E:\StudyBackups\backup_20260923_180000"
   ```
5. Start the local sync server:
   ```powershell
   dart run tool/local_sync_server.dart --host=0.0.0.0 --port=8787
   ```
6. Open the Admin Portal to confirm that records and conflicts match expectations.

### Scenario B: Restoring onto an Existing Installation (Overwrite Protection)

To prevent accidental data loss, the restore utility includes two safety layers:

1. **Explicit Confirmation**: If `.local_data/records.json` or `.local_data/conflicts.json` already exists, running `Restore` without `-ConfirmOverwrite` **aborts immediately** with an error message.
2. **Pre-Restore Safety Snapshot**: When `-ConfirmOverwrite` is passed, the utility automatically archives all existing live target files into a safety directory before replacing them:
   `.local_data\pre_restore_safety_backup_<yyyyMMdd_HHmmss>\`
3. **Atomic Replacement**: Files are written to temporary staging files first and moved atomically into place.

Command to restore with overwrite confirmation:

```powershell
powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 `
  -Action Restore `
  -BackupPath "E:\StudyBackups\backup_20260923_180000" `
  -ConfirmOverwrite
```

*(Direct Dart alternative: `dart run tool/backup_utility.dart restore --backup="E:\StudyBackups\backup_20260923_180000" --confirm-overwrite`)*

### Post-Restore Field Synchronization
After restoring:
- Field collectors reconnect during the next regular sync window.
- Visits previously synced are recognized via their persistent idempotency keys and will **not** create duplicate records.
- Visits completed on collector phones while the server was down will upload smoothly and safely.

---

## 6. Running the Automated Self-Test

The utility includes an automated, self-contained synthetic test suite that verifies the complete backup, tamper-detection, restore, and overwrite-safety lifecycle using temporary synthetic data.

Run the self-test with:

```powershell
powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action SelfTest
```

*(Direct Dart alternative: `dart run tool/backup_utility.dart test`)*

### What the Self-Test Validates:
- Generates synthetic visit records and conflict entries in a temporary directory.
- Executes an off-device backup to a temporary destination.
- Verifies backup manifest checksums and JSON schemas.
- **Tamper Detection**: Intentionally corrupts 1 byte in a copied backup and confirms that the verification engine flags the hash mismatch and aborts.
- **Safe Restore**: Restores the untampered backup to a fresh directory and confirms 100% data identity.
- **Overwrite Guard**: Proves that restoring into a populated directory is rejected when confirmation is omitted.
- **Safety Snapshot**: Proves that a pre-restore safety snapshot is created when confirmation is provided.
- Cleans up all temporary test directories on completion.

---

## 7. Troubleshooting & Failure Modes

### Error: Missing -Destination parameter
- **Cause**: `-Action Backup` was specified without providing a target path.
- **Fix**: Provide an external path: `-Destination "E:\StudyBackups"`.

### Error: Hash mismatch during verification (`[VERIFICATION FAILED]`)
- **Cause**: A file in the backup folder was altered, truncated, or suffered disk bit-rot.
- **Fix**: **Do NOT restore this backup.** Choose an earlier verified backup directory (e.g. from the previous day) or examine the storage medium for filesystem corruption.

### Error: Target directory already contains live data
- **Cause**: Running `-Action Restore` when `.local_data` already has database files.
- **Fix**: If you intend to overwrite the existing data, pass `-ConfirmOverwrite`. The utility will create a pre-restore safety snapshot before writing.

### Error: Source records file not found or invalid JSON
- **Cause**: `.local_data/records.json` is missing or was corrupted by manual editing.
- **Fix**: If corrupted, check whether `.local_data/records.json.bak` is valid, or restore from the latest verified off-device backup.

### Error: Disk Full
- **Cause**: The destination external drive ran out of available storage.
- **Fix**: The utility stages writes atomically; incomplete files are cleared. Free up space on the external drive or connect a new external drive and re-run.
