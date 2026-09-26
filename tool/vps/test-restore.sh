#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RESTORE_SCRIPT="$SCRIPT_DIR/restore-state.sh"
BACKUP_SCRIPT="$SCRIPT_DIR/backup-state.sh"

[[ -f "$RESTORE_SCRIPT" ]] || { echo "Error: restore-state.sh not found at $RESTORE_SCRIPT" >&2; exit 1; }
[[ -f "$BACKUP_SCRIPT" ]] || { echo "Error: backup-state.sh not found at $BACKUP_SCRIPT" >&2; exit 1; }

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/restore-test.XXXXXX")
cleanup_tests() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup_tests EXIT

pass_count=0
fail_count=0

assert_success() {
  local desc="$1"
  shift
  echo -n "  Running: $desc ... "
  if "$@"; then
    echo "PASS"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL"
    fail_count=$((fail_count + 1))
    echo "    Assertion failed: $*" >&2
    exit 1
  fi
}

assert_failure() {
  local desc="$1"
  shift
  echo -n "  Running: $desc ... "
  if "$@" >/dev/null 2>&1; then
    echo "FAIL (expected command to fail, but it succeeded)"
    fail_count=$((fail_count + 1))
    echo "    Command succeeded unexpectedly: $*" >&2
    exit 1
  else
    echo "PASS (failed as expected)"
    pass_count=$((pass_count + 1))
  fi
}

create_test_records_json() {
  local file="$1"
  local rec_id="$2"
  local name="${3:-Test Participant}"
  mkdir -p "$(dirname "$file")"
  cat <<EOF > "$file"
[
  {
    "id": "$rec_id",
    "name": "$name",
    "visitNumber": 1,
    "status": "submitted",
    "createdAt": "2026-09-26T00:00:00Z"
  }
]
EOF
}

generate_manifest() {
  local dir="$1"
  (
    cd "$dir"
    find . -type f ! -name 'SHA256SUMS' | LC_ALL=C sort | while IFS= read -r f; do
      sha256sum "$f"
    done > SHA256SUMS
  )
}

echo "=================================================================="
echo "Starting Safe State & Restore Test Suite"
echo "Test Root: $TEST_ROOT"
echo "=================================================================="

# ------------------------------------------------------------------
# TEST 1: Successful restore replaces state completely and removes stale files
# ------------------------------------------------------------------
echo
echo "--- TEST 1: Successful restore replaces state completely and removes old stale files ---"
t1_dir="$TEST_ROOT/test1"
t1_target="$t1_dir/state"
t1_backup="$t1_dir/backup"
mkdir -p "$t1_target" "$t1_backup"

# Setup target state with existing records AND stale files
create_test_records_json "$t1_target/records.json" "old-rec-001" "Old State Participant"
create_test_records_json "$t1_target/.local_data/records.json" "old-rec-001" "Old State Participant"
echo "stale cache data" > "$t1_target/stale_cache.log"
echo "extra stray file" > "$t1_target/stale_file.txt"
mkdir -p "$t1_target/stale_dir"
echo "stale nested data" > "$t1_target/stale_dir/stale_nested.json"

# Setup backup with new records
create_test_records_json "$t1_backup/records.json" "new-rec-100" "New Restored Participant"
create_test_records_json "$t1_backup/.local_data/records.json" "new-rec-100" "New Restored Participant"
generate_manifest "$t1_backup"

assert_success "Run restore-state.sh on valid backup" \
  bash "$RESTORE_SCRIPT" "$t1_backup" "$t1_target"

# Verify new records are present
test_t1_content() {
  grep -q "new-rec-100" "$t1_target/records.json" && \
  grep -q "new-rec-100" "$t1_target/.local_data/records.json" && \
  ! grep -q "old-rec-001" "$t1_target/records.json"
}
assert_success "Restored records exist in target and old records replaced" test_t1_content

# Verify stale files are completely eliminated
test_t1_no_stale() {
  [[ ! -e "$t1_target/stale_cache.log" ]] && \
  [[ ! -e "$t1_target/stale_file.txt" ]] && \
  [[ ! -e "$t1_target/stale_dir" ]]
}
assert_success "All old stale files and directories were cleanly removed" test_t1_no_stale

# Verify pre-restore safety backup was created outside target state directory
test_t1_safety_backup() {
  local safety_base="$t1_dir/pre_restore_safety_backups"
  [[ -d "$safety_base" ]] || return 1
  local found_backup=0
  for sb in "$safety_base"/safety_backup_*; do
    if [[ -d "$sb" && -f "$sb/records.json" && -f "$sb/SHA256SUMS" ]]; then
      grep -q "old-rec-001" "$sb/records.json" && found_backup=1
    fi
  done
  [[ $found_backup -eq 1 ]]
}
assert_success "Pre-restore safety backup preserved outside target with old state" test_t1_safety_backup

# Verify no swap directories left
test_t1_no_swap() {
  local count
  count=$(find "$t1_dir" -maxdepth 1 -name 'state.pre_swap.*' | wc -l | tr -d ' ')
  [[ "$count" -eq 0 ]]
}
assert_success "Temporary swap path cleanly removed after success" test_t1_no_swap

# ------------------------------------------------------------------
# TEST 2: Corrupt checksum in backup is rejected during staging; target untouched
# ------------------------------------------------------------------
echo
echo "--- TEST 2: Corrupt checksum rejected during staging verification; target state untouched ---"
t2_dir="$TEST_ROOT/test2"
t2_target="$t2_dir/state"
t2_backup="$t2_dir/backup"
mkdir -p "$t2_target" "$t2_backup"

# Setup target state
create_test_records_json "$t2_target/records.json" "preserve-rec-002"
echo "canary_t2_content" > "$t2_target/canary.txt"

# Setup backup and tamper with it
create_test_records_json "$t2_backup/records.json" "tampered-rec-002"
generate_manifest "$t2_backup"
# Corrupt records.json so SHA256 checksum mismatches
echo "tampered byte" >> "$t2_backup/records.json"

assert_failure "Reject restore when checksum manifest verification fails" \
  bash "$RESTORE_SCRIPT" "$t2_backup" "$t2_target"

# Verify target state was untouched
test_t2_target_untouched() {
  [[ -f "$t2_target/canary.txt" ]] && \
  [[ "$(cat "$t2_target/canary.txt")" == "canary_t2_content" ]] && \
  grep -q "preserve-rec-002" "$t2_target/records.json" && \
  ! grep -q "tampered-rec-002" "$t2_target/records.json"
}
assert_success "Target state was completely untouched by failed restore" test_t2_target_untouched

# Verify no leftover staging or swap directory in target parent
test_t2_no_leftover_artifacts() {
  local leftovers
  leftovers=$(find "$t2_dir" -maxdepth 1 -name '.restore_staging_*' -o -name 'state.pre_swap.*' | wc -l | tr -d ' ')
  [[ "$leftovers" -eq 0 ]]
}
assert_success "No staging or swap artifacts left behind" test_t2_no_leftover_artifacts

# ------------------------------------------------------------------
# TEST 3: Empty backup or missing manifest is rejected; target state untouched
# ------------------------------------------------------------------
echo
echo "--- TEST 3: Empty backup or missing manifest is rejected; target state untouched ---"
t3_dir="$TEST_ROOT/test3"
t3_target="$t3_dir/state"
mkdir -p "$t3_target"
create_test_records_json "$t3_target/records.json" "preserve-rec-003"
echo "canary_t3" > "$t3_target/canary.txt"

# 3a: Missing SHA256SUMS manifest
t3_backup_nomanifest="$t3_dir/backup_nomanifest"
mkdir -p "$t3_backup_nomanifest"
create_test_records_json "$t3_backup_nomanifest/records.json" "bad-rec-003a"
assert_failure "Reject backup missing SHA256SUMS manifest" \
  bash "$RESTORE_SCRIPT" "$t3_backup_nomanifest" "$t3_target"

# 3b: Empty backup directory
t3_backup_empty="$t3_dir/backup_empty"
mkdir -p "$t3_backup_empty"
assert_failure "Reject completely empty backup directory" \
  bash "$RESTORE_SCRIPT" "$t3_backup_empty" "$t3_target"

# 3c: Backup containing only EMPTY_STATE marker (no records.json)
t3_backup_emptystate="$t3_dir/backup_emptystate"
mkdir -p "$t3_backup_emptystate"
touch "$t3_backup_emptystate/EMPTY_STATE"
generate_manifest "$t3_backup_emptystate"
assert_failure "Reject backup lacking records.json even if EMPTY_STATE manifest is valid" \
  bash "$RESTORE_SCRIPT" "$t3_backup_emptystate" "$t3_target"

# 3d: Backup containing invalid/corrupt JSON in records.json
t3_backup_badjson="$t3_dir/backup_badjson"
mkdir -p "$t3_backup_badjson"
echo "{ this is definitely not valid json list" > "$t3_backup_badjson/records.json"
generate_manifest "$t3_backup_badjson"
assert_failure "Reject backup containing malformed JSON in records.json" \
  bash "$RESTORE_SCRIPT" "$t3_backup_badjson" "$t3_target"

test_t3_target_untouched() {
  [[ -f "$t3_target/canary.txt" ]] && \
  [[ "$(cat "$t3_target/canary.txt")" == "canary_t3" ]] && \
  grep -q "preserve-rec-003" "$t3_target/records.json"
}
assert_success "Target state remained untouched across all invalid/empty backup tests" test_t3_target_untouched

# ------------------------------------------------------------------
# TEST 4: Unsafe paths (target /, traversal .., symlinks pointing outside, overlap) rejected
# ------------------------------------------------------------------
echo
echo "--- TEST 4: Unsafe paths rejected (target /, traversal .., symlinks pointing outside, overlap) ---"
t4_dir="$TEST_ROOT/test4"
t4_valid_backup="$t4_dir/valid_backup"
t4_target="$t4_dir/safe_state"
mkdir -p "$t4_valid_backup" "$t4_target"
create_test_records_json "$t4_valid_backup/records.json" "rec-004"
generate_manifest "$t4_valid_backup"

# 4a: Target is / or broad system directories
assert_failure "Reject target directory '/'" \
  bash "$RESTORE_SCRIPT" "$t4_valid_backup" "/"

assert_failure "Reject broad target directory '/var'" \
  bash "$RESTORE_SCRIPT" "$t4_valid_backup" "/var"

assert_failure "Reject broad target directory '/tmp'" \
  bash "$RESTORE_SCRIPT" "$t4_valid_backup" "/tmp"

assert_failure "Reject broad target directory '/etc'" \
  bash "$RESTORE_SCRIPT" "$t4_valid_backup" "/etc"

# 4b: Directory traversal ..
assert_failure "Reject backup path containing directory traversal ('..')" \
  bash "$RESTORE_SCRIPT" "$t4_dir/../test4/valid_backup" "$t4_target"

assert_failure "Reject target path containing directory traversal ('..')" \
  bash "$RESTORE_SCRIPT" "$t4_valid_backup" "$t4_dir/../test4/safe_state"

# 4c: Overlapping paths
assert_failure "Reject identical source and target directory" \
  bash "$RESTORE_SCRIPT" "$t4_valid_backup" "$t4_valid_backup"

t4_sub_target="$t4_valid_backup/nested_target"
assert_failure "Reject target directory nested inside backup source" \
  bash "$RESTORE_SCRIPT" "$t4_valid_backup" "$t4_sub_target"

t4_nested_backup="$t4_target/nested_backup"
mkdir -p "$t4_nested_backup"
create_test_records_json "$t4_nested_backup/records.json" "rec-004-sub"
generate_manifest "$t4_nested_backup"
assert_failure "Reject backup source nested inside target directory" \
  bash "$RESTORE_SCRIPT" "$t4_nested_backup" "$t4_target"

# 4d: Symlinks pointing outside
t4_symlink_backup="$t4_dir/symlink_backup"
mkdir -p "$t4_symlink_backup"
create_test_records_json "$t4_symlink_backup/records.json" "rec-004-sym"
export MSYS="winsymlinks:lnk"
# Create symlink pointing outside staging
ln -s "/outside_file" "$t4_symlink_backup/evil_link" 2>/dev/null || true
generate_manifest "$t4_symlink_backup"

if [[ -L "$t4_symlink_backup/evil_link" ]]; then
  assert_failure "Reject backup staging containing symlink pointing outside staging" \
    bash "$RESTORE_SCRIPT" "$t4_symlink_backup" "$t4_target"
else
  # Emulate via tarball containing symlink if filesystem ln -s did not create L
  python -c "
import tarfile
t = tarfile.open('$t4_symlink_backup/evil_tar.tar', 'w')
ti = tarfile.TarInfo('evil_link')
ti.type = tarfile.SYMTYPE
ti.linkname = '/outside_file'
t.addfile(ti)
t.close()
" 2>/dev/null || true
  if [[ -f "$t4_symlink_backup/evil_tar.tar" ]]; then
    (cd "$t4_symlink_backup" && tar -xf evil_tar.tar 2>/dev/null && rm evil_tar.tar) || true
    generate_manifest "$t4_symlink_backup"
    if [[ -L "$t4_symlink_backup/evil_link" ]]; then
      assert_failure "Reject backup staging containing symlink pointing outside staging" \
        bash "$RESTORE_SCRIPT" "$t4_symlink_backup" "$t4_target"
    else
      echo "  Notice: Symlink creation not permitted on host; verified boundary checks for traversal and targets."
    fi
  fi
fi

# Reject target directory if it is a symbolic link
t4_target_link="$t4_dir/symlink_target"
ln -s "$t4_target" "$t4_target_link" 2>/dev/null || true
if [[ -L "$t4_target_link" ]]; then
  assert_failure "Reject target directory when target is a symbolic link" \
    bash "$RESTORE_SCRIPT" "$t4_valid_backup" "$t4_target_link"
fi

# ------------------------------------------------------------------
# TEST 5: Failure during restore triggers automatic rollback to pre-restore state
# ------------------------------------------------------------------
echo
echo "--- TEST 5: Failure during restore triggers automatic rollback to pre-restore state ---"
t5_dir="$TEST_ROOT/test5"
t5_target="$t5_dir/state"
t5_backup="$t5_dir/backup"
t5_mock_bin="$t5_dir/mock_bin"
t5_mock_log="$t5_dir/mock_systemctl.log"
mkdir -p "$t5_target" "$t5_backup" "$t5_mock_bin"

create_test_records_json "$t5_target/records.json" "pre-fail-rec-005" "Original State Prior To Crash"
echo "canary_t5_active_state" > "$t5_target/canary.txt"

create_test_records_json "$t5_backup/records.json" "uncommitted-new-005" "Should Roll Back"
generate_manifest "$t5_backup"

# Create mock systemctl in PATH
cat <<EOF > "$t5_mock_bin/systemctl"
#!/usr/bin/env bash
echo "\$@" >> "$t5_mock_log"
case "\$1" in
  is-active)
    exit 0
    ;;
  stop)
    exit 0
    ;;
  start)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$t5_mock_bin/systemctl"

assert_failure "Restore failure triggered via test hook exits non-zero" \
  env PATH="$t5_mock_bin:$PATH" _VPS_RESTORE_FAIL_POINT=after_swap \
  bash "$RESTORE_SCRIPT" "$t5_backup" "$t5_target"

# Verify target state was rolled back to original pre-restore state
test_t5_rollback_content() {
  [[ -f "$t5_target/canary.txt" ]] && \
  [[ "$(cat "$t5_target/canary.txt")" == "canary_t5_active_state" ]] && \
  grep -q "pre-fail-rec-005" "$t5_target/records.json" && \
  ! grep -q "uncommitted-new-005" "$t5_target/records.json"
}
assert_success "Automatic rollback successfully restored original state files" test_t5_rollback_content

# Verify service was stopped then restarted during rollback
test_t5_service_restored() {
  [[ -f "$t5_mock_log" ]] && \
  grep -q "stop plus5-vps" "$t5_mock_log" && \
  grep -q "start plus5-vps" "$t5_mock_log"
}
assert_success "Service was quiesced before swap and restarted during rollback" test_t5_service_restored

# Verify swap directory was cleaned up during rollback
test_t5_swap_cleaned() {
  local leftovers
  leftovers=$(find "$t5_dir" -maxdepth 1 -name 'state.pre_swap.*' | wc -l | tr -d ' ')
  [[ "$leftovers" -eq 0 ]]
}
assert_success "Swap temporary directory cleaned up during rollback" test_t5_swap_cleaned

# ------------------------------------------------------------------
# TEST 6: backup-state.sh and restore-state.sh end-to-end integration & safety checks
# ------------------------------------------------------------------
echo
echo "--- TEST 6: backup-state.sh and restore-state.sh end-to-end integration & safety checks ---"
t6_dir="$TEST_ROOT/test6"
t6_state="$t6_dir/state"
t6_dest="$t6_dir/backups"
t6_restore_target="$t6_dir/restored_state"
mkdir -p "$t6_state" "$t6_dest" "$t6_restore_target"

create_test_records_json "$t6_state/records.json" "e2e-rec-006" "End to End Participant"
create_test_records_json "$t6_state/.local_data/records.json" "e2e-rec-006" "End to End Participant"

# Test backup-state.sh safety validations
assert_failure "backup-state.sh rejects destination directory containing '..'" \
  bash "$BACKUP_SCRIPT" --force-same-filesystem "$t6_dir/../test6/backups"

assert_failure "backup-state.sh rejects destination '/'" \
  bash "$BACKUP_SCRIPT" --force-same-filesystem "/"

assert_failure "backup-state.sh rejects destination inside state directory" \
  env VPS_STATE_DIR="$t6_state" bash "$BACKUP_SCRIPT" --force-same-filesystem "$t6_state/nested_backup"

# Run valid backup
assert_success "Create backup using backup-state.sh" \
  env VPS_STATE_DIR="$t6_state" bash "$BACKUP_SCRIPT" --force-same-filesystem "$t6_dest"

# Find generated backup directory after backup creation
test_t6_backup_exists() {
  generated_backup=$(find "$t6_dest" -mindepth 1 -maxdepth 1 -type d -name 'backup_*' | head -n 1)
  [[ -n "$generated_backup" && -d "$generated_backup" && -f "$generated_backup/SHA256SUMS" ]]
}
assert_success "backup-state.sh produced valid backup folder with manifest" test_t6_backup_exists

# Restore using restore-state.sh
do_t6_restore() {
  generated_backup=$(find "$t6_dest" -mindepth 1 -maxdepth 1 -type d -name 'backup_*' | head -n 1)
  bash "$RESTORE_SCRIPT" "$generated_backup" "$t6_restore_target"
}
assert_success "Restore state from backup created by backup-state.sh" do_t6_restore

test_t6_restored_content() {
  grep -q "e2e-rec-006" "$t6_restore_target/records.json" && \
  grep -q "e2e-rec-006" "$t6_restore_target/.local_data/records.json"
}
assert_success "End-to-end backup and restore verified data integrity" test_t6_restored_content

echo
echo "=================================================================="
echo "TEST SUMMARY:"
echo "  Passed: $pass_count"
echo "  Failed: $fail_count"
echo "=================================================================="

if [[ $fail_count -gt 0 ]]; then
  echo "OVERALL STATUS: FAIL" >&2
  exit 1
else
  echo "OVERALL STATUS: ALL TESTS PASSED (SUCCESS)"
  exit 0
fi

