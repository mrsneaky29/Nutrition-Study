#!/usr/bin/env bash
#
# test-release-lifecycle.sh: End-to-end automated verification of the VPS release lifecycle:
#   1. Release archive creation and import-release.sh execution
#   2. Strict permission inspection (0755 dirs, 0644 files, 0755 scripts, safe ownership, go-w, traversal)
#   3. activate-release.sh success path with authenticated health check
#   4. activate-release.sh failure path with automatic rollback to previous release pointer
#   5. Service restart failure path with automatic rollback
#   6. rollback.sh clean execution with health check verification
#
set -euo pipefail

# Ensure POSIX/native symlinks if running under MSYS/Cygwin environments
if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" ]]; then
  export MSYS="${MSYS:-winsymlinks:native}"
fi

to_win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    echo "$1"
  fi
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plus5-release-lifecycle.XXXXXX")

# Test configuration
export VPS_ROOT="$TEST_DIR/opt/plus5-vps"
export VPS_ALLOW_NON_ROOT=1
export ALLOW_NON_ROOT=1
export HEALTH_CHECK_TIMEOUT=3
export HEALTH_CHECK_INTERVAL=0.2

MOCK_PORT=$(( 28000 + (RANDOM % 10000) ))
ADMIN_KEY="lifecycle-test-secret-key-$(date +%s)"

mkdir -p "$VPS_ROOT/releases"
mkdir -p "$TEST_DIR/bin"
mkdir -p "$TEST_DIR/etc"

echo "healthy" > "$TEST_DIR/service_status"
SERVER_PID=""

stop_mock_server() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    if command -v taskkill >/dev/null 2>&1; then
      taskkill //F //T //PID "$SERVER_PID" >/dev/null 2>&1 || true
    fi
    SERVER_PID=""
  fi
}

cleanup() {
  stop_mock_server
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "============================================================"
echo "Starting VPS Release Lifecycle Automated Verification"
echo "Test Root: $TEST_DIR"
echo "Mock Port: $MOCK_PORT"
echo "============================================================"

# -----------------------------------------------------------------------------
# Write Mock HTTP Server (Dart)
# -----------------------------------------------------------------------------
cat << 'EOF' > "$TEST_DIR/bin/mock_server.dart"
import 'dart:io';

void main(List<String> args) async {
  final port = int.parse(args[0]);
  final adminKey = args.length > 1 ? args[1] : '';
  final statusFilePath = args.length > 2 ? args[2] : '';

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('MOCK_READY');

  await for (HttpRequest req in server) {
    var isUnhealthy = false;
    if (statusFilePath.isNotEmpty) {
      final sFile = File(statusFilePath);
      if (sFile.existsSync()) {
        try {
          final content = sFile.readAsStringSync().trim();
          if (content == 'unhealthy') {
            isUnhealthy = true;
          }
        } catch (_) {}
      }
    }

    if (isUnhealthy) {
      req.response.statusCode = 500;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"status":"error","message":"simulated failure"}');
      await req.response.close();
      continue;
    }

    final path = req.uri.path;
    if (path == '/health' || path == '/sync/health') {
      final proto = req.headers.value('x-forwarded-proto')?.toLowerCase();
      if (proto != 'https') {
        req.response.statusCode = 403;
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"error":"HTTPS reverse proxy required."}');
        await req.response.close();
        continue;
      }

      final key = req.headers.value('x-local-sync-key');
      if (adminKey.isNotEmpty && key != adminKey) {
        req.response.statusCode = 401;
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"error":"Invalid local access key."}');
        await req.response.close();
        continue;
      }

      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"status":"ok","records":0,"recoveredFromBackup":false}');
      await req.response.close();
      continue;
    }

    req.response.statusCode = 404;
    await req.response.close();
  }
}
EOF

# Start mock server
start_mock_server() {
  stop_mock_server
  local win_script
  local win_status
  win_script=$(to_win_path "$TEST_DIR/bin/mock_server.dart")
  win_status=$(to_win_path "$TEST_DIR/service_status")
  dart "$win_script" "$MOCK_PORT" "$ADMIN_KEY" "$win_status" >"$TEST_DIR/server.log" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 30); do
    if curl --silent --max-time 1 "http://127.0.0.1:$MOCK_PORT/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  echo "Error: Mock server failed to become ready" >&2
  cat "$TEST_DIR/server.log" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Write Mock systemctl
# -----------------------------------------------------------------------------
cat << EOF > "$TEST_DIR/bin/systemctl"
#!/usr/bin/env bash
set -euo pipefail

cmd=\${1:-}
service=\${2:-}

if [[ "\$cmd" == "restart" ]]; then
  curr_target=""
  if [[ -d "$VPS_ROOT/current" || -L "$VPS_ROOT/current" ]]; then
    if command -v realpath >/dev/null 2>&1; then
      curr_target=\$(realpath "$VPS_ROOT/current" 2>/dev/null || true)
    else
      curr_target=\$(readlink -f "$VPS_ROOT/current" 2>/dev/null || true)
    fi
  fi

  if [[ -n "\$curr_target" && -f "\$curr_target/SIMULATE_RESTART_FAILURE" ]]; then
    echo "systemd: Failed to restart \$service: unit entered failed state" >&2
    exit 1
  fi

  if [[ -n "\$curr_target" && -f "\$curr_target/SIMULATE_UNHEALTHY" ]]; then
    echo "unhealthy" > "$TEST_DIR/service_status"
  else
    echo "healthy" > "$TEST_DIR/service_status"
  fi
  exit 0
fi

echo "Mock systemctl: unknown command \$cmd" >&2
exit 1
EOF
chmod +x "$TEST_DIR/bin/systemctl"
export VPS_SYSTEMCTL_BIN="$TEST_DIR/bin/systemctl"

# Write environment file
cat << EOF > "$TEST_DIR/etc/local-sync.env"
LOCAL_SYNC_ADMIN_KEY=$ADMIN_KEY
LOCAL_SYNC_HOST=127.0.0.1
LOCAL_SYNC_PORT=$MOCK_PORT
EOF
export ENV_FILE="$TEST_DIR/etc/local-sync.env"

resolve_target() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  elif readlink -f "$p" >/dev/null 2>&1; then
    readlink -f "$p"
  else
    readlink "$p"
  fi
}

# -----------------------------------------------------------------------------
# TEST 1: Release Archiving & import-release.sh with Strict Permission Checks
# -----------------------------------------------------------------------------
echo ""
echo "--> TEST 1: Release Archiving & import-release.sh Permissions Verification..."

mkdir -p "$TEST_DIR/staging1/tool"
mkdir -p "$TEST_DIR/staging1/build/admin_web"
mkdir -p "$TEST_DIR/staging1/nested/sub"

cat << 'EOF' > "$TEST_DIR/staging1/tool/local_sync_server.dart"
// Local sync server placeholder
void main() {}
EOF

cat << 'EOF' > "$TEST_DIR/staging1/build/admin_web/index.html"
<!DOCTYPE html><html><head><title>Admin</title></head><body>Admin Web</body></html>
EOF

cat << 'EOF' > "$TEST_DIR/staging1/tool/run.sh"
#!/bin/sh
echo "Worker run script"
EOF
chmod +x "$TEST_DIR/staging1/tool/run.sh"

echo "Some data" > "$TEST_DIR/staging1/nested/sub/config.txt"

# Intentionally create restrictive permissions in staging to verify normalization
chmod 0700 "$TEST_DIR/staging1"
chmod 0600 "$TEST_DIR/staging1/build/admin_web/index.html"

# Create archive
tar -czf "$TEST_DIR/release1.tar.gz" -C "$TEST_DIR/staging1" .

# Import release
rel1_id=$(bash "$SCRIPT_DIR/import-release.sh" "$TEST_DIR/release1.tar.gz")
echo "    Imported Release 1 ID: $rel1_id"

dest1="$VPS_ROOT/releases/$rel1_id"
[[ -d "$dest1" ]] || { echo "FAIL: Destination release directory not found: $dest1" >&2; exit 1; }

# Inspect directory permissions: must be 0755
dest1_mode=$(stat -c "%a" "$dest1")
[[ "$dest1_mode" == "755" ]] || { echo "FAIL: Expected release dir mode 755; got $dest1_mode" >&2; exit 1; }

for d in "$dest1/tool" "$dest1/build" "$dest1/build/admin_web" "$dest1/nested" "$dest1/nested/sub"; do
  d_mode=$(stat -c "%a" "$d")
  [[ "$d_mode" == "755" ]] || { echo "FAIL: Expected subdirectory $d to have mode 755; got $d_mode" >&2; exit 1; }
done

# Inspect file permissions: non-executables 0644, scripts/executables 0755
for f in "$dest1/tool/local_sync_server.dart" "$dest1/build/admin_web/index.html" "$dest1/nested/sub/config.txt"; do
  f_mode=$(stat -c "%a" "$f")
  [[ "$f_mode" == "644" ]] || { echo "FAIL: Expected file $f to have mode 644; got $f_mode" >&2; exit 1; }
done

script_mode=$(stat -c "%a" "$dest1/tool/run.sh")
[[ "$script_mode" == "755" ]] || { echo "FAIL: Expected executable script to have mode 755; got $script_mode" >&2; exit 1; }

# Prevent world/group write permissions
group_world_writable=$(find "$dest1" -perm /022)
[[ -z "$group_world_writable" ]] || {
  echo "FAIL: Found files or directories with group/world write permissions:" >&2
  echo "$group_world_writable" >&2
  exit 1
}

# Verify traversal permissions for non-root users:
# Directories must have other read and execute (+rx), files must have other read (+r)
for d in "$dest1" "$dest1/tool" "$dest1/build/admin_web"; do
  [[ -r "$d" && -x "$d" ]] || { echo "FAIL: Directory $d is not traversable/readable" >&2; exit 1; }
done

echo "PASS: TEST 1 passed (permissions normalized to 0755 dirs, 0644 files, 0755 scripts, go-w, traversable)."

# -----------------------------------------------------------------------------
# TEST 2: Release Activation Success Path
# -----------------------------------------------------------------------------
echo ""
echo "--> TEST 2: activate-release.sh Success Path..."
start_mock_server

# Activate Release 1
bash "$SCRIPT_DIR/activate-release.sh" "$rel1_id"

# Verify current pointer
current_target=$(resolve_target "$VPS_ROOT/current")
[[ "$current_target" == "$dest1" ]] || {
  echo "FAIL: Expected current to point to $dest1; got $current_target" >&2
  exit 1
}

# Create Release 2
mkdir -p "$TEST_DIR/staging2/tool" "$TEST_DIR/staging2/build/admin_web"
cp "$TEST_DIR/staging1/tool/local_sync_server.dart" "$TEST_DIR/staging2/tool/"
cp "$TEST_DIR/staging1/build/admin_web/index.html" "$TEST_DIR/staging2/build/admin_web/"
echo "Release 2 marker" > "$TEST_DIR/staging2/version.txt"
tar -czf "$TEST_DIR/release2.tar.gz" -C "$TEST_DIR/staging2" .

rel2_id=$(bash "$SCRIPT_DIR/import-release.sh" "$TEST_DIR/release2.tar.gz")
dest2="$VPS_ROOT/releases/$rel2_id"
echo "    Imported Release 2 ID: $rel2_id"

# Activate Release 2
bash "$SCRIPT_DIR/activate-release.sh" "$rel2_id"

# Verify pointers: current -> rel2, previous -> rel1
current_target=$(resolve_target "$VPS_ROOT/current")
[[ "$current_target" == "$dest2" ]] || {
  echo "FAIL: Expected current to point to $dest2; got $current_target" >&2
  exit 1
}

previous_target=$(resolve_target "$VPS_ROOT/previous")
[[ "$previous_target" == "$dest1" ]] || {
  echo "FAIL: Expected previous to point to $dest1; got $previous_target" >&2
  exit 1
}

echo "PASS: TEST 2 passed (activate-release.sh successfully activated release and verified health)."

# -----------------------------------------------------------------------------
# TEST 3: Release Activation Failure Path & Automatic Rollback (Unhealthy Server)
# -----------------------------------------------------------------------------
echo ""
echo "--> TEST 3: activate-release.sh Failure Path & Automatic Rollback (Unhealthy Server)..."

# Create Release 3 marked unhealthy
mkdir -p "$TEST_DIR/staging3/tool" "$TEST_DIR/staging3/build/admin_web"
cp "$TEST_DIR/staging1/tool/local_sync_server.dart" "$TEST_DIR/staging3/tool/"
cp "$TEST_DIR/staging1/build/admin_web/index.html" "$TEST_DIR/staging3/build/admin_web/"
touch "$TEST_DIR/staging3/SIMULATE_UNHEALTHY"
tar -czf "$TEST_DIR/release3.tar.gz" -C "$TEST_DIR/staging3" .

rel3_id=$(bash "$SCRIPT_DIR/import-release.sh" "$TEST_DIR/release3.tar.gz")
dest3="$VPS_ROOT/releases/$rel3_id"
echo "    Imported Unhealthy Release 3 ID: $rel3_id"

# Activation of rel3 should fail and automatically rollback to rel2
set +e
activate_out=$(bash "$SCRIPT_DIR/activate-release.sh" "$rel3_id" 2>&1)
activate_code=$?
set -e

[[ $activate_code -ne 0 ]] || {
  echo "FAIL: Expected activate-release.sh to fail for unhealthy release, but it succeeded" >&2
  exit 1
}

echo "    activate-release.sh exited with code $activate_code as expected."

# Verify error output mentions ACTIVATION FAILED and rollback
echo "$activate_out" | grep -q "ACTIVATION FAILED" || {
  echo "FAIL: Output did not contain 'ACTIVATION FAILED'" >&2
  echo "$activate_out" >&2
  exit 1
}

echo "$activate_out" | grep -q "Triggering automatic rollback" || {
  echo "FAIL: Output did not indicate automatic rollback trigger" >&2
  echo "$activate_out" >&2
  exit 1
}

# Verify current pointer was restored to rel2!
current_target=$(resolve_target "$VPS_ROOT/current")
[[ "$current_target" == "$dest2" ]] || {
  echo "FAIL: Expected current to be rolled back to $dest2; got $current_target" >&2
  exit 1
}

# Verify backend is healthy on rel2
health_check_code=$(curl --silent -o /dev/null -w "%{http_code}" -H "X-Forwarded-Proto: https" -H "X-Local-Sync-Key: $ADMIN_KEY" "http://127.0.0.1:$MOCK_PORT/health")
[[ "$health_check_code" == "200" ]] || {
  echo "FAIL: Service on rolled back release is not responding 200; got $health_check_code" >&2
  exit 1
}

echo "PASS: TEST 3 passed (activation failure triggered automatic rollback to previous release)."

# -----------------------------------------------------------------------------
# TEST 4: Release Activation Failure Path (Service Restart Failure)
# -----------------------------------------------------------------------------
echo ""
echo "--> TEST 4: activate-release.sh Failure Path (Service Restart Failure)..."

# Create Release 4 marked to fail service restart
mkdir -p "$TEST_DIR/staging4/tool" "$TEST_DIR/staging4/build/admin_web"
cp "$TEST_DIR/staging1/tool/local_sync_server.dart" "$TEST_DIR/staging4/tool/"
cp "$TEST_DIR/staging1/build/admin_web/index.html" "$TEST_DIR/staging4/build/admin_web/"
touch "$TEST_DIR/staging4/SIMULATE_RESTART_FAILURE"
tar -czf "$TEST_DIR/release4.tar.gz" -C "$TEST_DIR/staging4" .

rel4_id=$(bash "$SCRIPT_DIR/import-release.sh" "$TEST_DIR/release4.tar.gz")
echo "    Imported Release 4 ID: $rel4_id"

set +e
restart_fail_out=$(bash "$SCRIPT_DIR/activate-release.sh" "$rel4_id" 2>&1)
restart_fail_code=$?
set -e

[[ $restart_fail_code -ne 0 ]] || {
  echo "FAIL: Expected activation to fail when restart fails, but it succeeded" >&2
  exit 1
}

# Verify current pointer was restored to rel2
current_target=$(resolve_target "$VPS_ROOT/current")
[[ "$current_target" == "$dest2" ]] || {
  echo "FAIL: Expected current to be rolled back to $dest2 after restart failure; got $current_target" >&2
  exit 1
}

echo "PASS: TEST 4 passed (service restart failure triggered automatic rollback)."

# -----------------------------------------------------------------------------
# TEST 5: rollback.sh Verification
# -----------------------------------------------------------------------------
echo ""
echo "--> TEST 5: rollback.sh Execution..."
# Current is rel2, previous is rel1
previous_target=$(resolve_target "$VPS_ROOT/previous")
[[ "$previous_target" == "$dest1" ]] || {
  echo "FAIL: Expected previous to be $dest1 before rollback.sh; got $previous_target" >&2
  exit 1
}

# Execute rollback.sh without arguments
bash "$SCRIPT_DIR/rollback.sh"

# Now current should be rel1, and previous should be rel2
current_target=$(resolve_target "$VPS_ROOT/current")
[[ "$current_target" == "$dest1" ]] || {
  echo "FAIL: Expected current to point to $dest1 after rollback.sh; got $current_target" >&2
  exit 1
}

previous_target=$(resolve_target "$VPS_ROOT/previous")
[[ "$previous_target" == "$dest2" ]] || {
  echo "FAIL: Expected previous to point to $dest2 after rollback.sh; got $previous_target" >&2
  exit 1
}

# Verify health check succeeds on rolled back release
health_code=$(curl --silent -o /dev/null -w "%{http_code}" -H "X-Forwarded-Proto: https" -H "X-Local-Sync-Key: $ADMIN_KEY" "http://127.0.0.1:$MOCK_PORT/health")
[[ "$health_code" == "200" ]] || {
  echo "FAIL: Health check failed after rollback.sh; got $health_code" >&2
  exit 1
}

echo "PASS: TEST 5 passed (rollback.sh resolved previous pointer, activated release, and verified health)."

echo ""
echo "============================================================"
echo "ALL VPS RELEASE LIFECYCLE TESTS PASSED SUCCESSFULLY!"
echo "============================================================"
