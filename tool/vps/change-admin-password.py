"""Interactive, admin-only credential rotation. Never print or log secrets."""
import datetime
import getpass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ENV = Path('/etc/plus5-vps/local-sync.env')
SOURCE = Path('/opt/plus5-vps/current/tool/local_sync_server.dart')
STATUS = Path('/run/vivayu-admin-password-change.json')


def environment():
    pid = subprocess.check_output(['systemctl', 'show', 'plus5-vps', '--property=MainPID', '--value'], text=True).strip()
    return dict(part.decode('utf-8').split('=', 1) for part in Path('/proc', pid, 'environ').read_bytes().split(b'\0') if b'=' in part)


def health(password):
    request = urllib.request.Request('http://127.0.0.1:8787/health', headers={'x-local-sync-key': password, 'x-forwarded-proto': 'https'})
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, {}


def atomic_write(path, data, metadata):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        os.fchmod(fd, metadata.st_mode & 0o777)
        os.fchown(fd, metadata.st_uid, metadata.st_gid)
        with os.fdopen(fd, 'wb') as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def save_status(success, message):
    STATUS.write_text(json.dumps({'success': success, 'message': message, 'finishedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()}))
    STATUS.chmod(0o600)


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run this prompt using the existing root SSH account.')
    actual = environment()
    old_password = actual.get('LOCAL_SYNC_ADMIN_KEY', '')
    if actual.get('LOCAL_SYNC_PUBLIC_MODE') != 'true' or not old_password:
        raise SystemExit('Unexpected service configuration. Nothing changed.')
    collectors = actual.get('LOCAL_SYNC_COLLECTOR_KEYS', '')
    if sys.argv[1:] == ['--check']:
        code, _ = health(old_password)
        if code != 200:
            raise SystemExit('Existing authenticated health check failed (status ' + str(code) + ').')
        print('PASS: current authenticated API health; no configuration changed.')
        return
    while True:
        password = getpass.getpass('New Vivayu dashboard password: ').strip()
        if not password:
            print('Enter a password; it cannot be blank.')
            continue
        if password == old_password:
            print('That is the current password. Enter a new one.')
            continue
        if any(password == entry.split(':', 1)[-1] for entry in collectors.split(',')):
            print('That value is already used by a collector. Enter a different admin password.')
            continue
        if password != getpass.getpass('Confirm new password: ').strip():
            print('Passwords did not match. Please try again.')
            continue
        # Validate compatibility with the existing browser/header login before mutation.
        urllib.request.Request('http://127.0.0.1:8787/health', headers={'x-local-sync-key': password})
        break
    code, previous_health = health(old_password)
    if code != 200:
        raise SystemExit('The existing API did not pass its health check. Nothing changed.')
    old_env, old_source = ENV.read_bytes(), SOURCE.read_bytes()
    env_metadata, source_metadata = ENV.stat(), SOURCE.stat()
    old_check = b'rawCollectors.isEmpty || rawAdmin.length < _publicMinKeyLength'
    new_check = b'rawCollectors.isEmpty || rawAdmin.isEmpty'
    if old_source.count(old_check) == 1:
        new_source = old_source.replace(old_check, new_check).replace(
            b'LOCAL_SYNC_COLLECTOR_KEYS and a LOCAL_SYNC_ADMIN_KEY of at least 32 characters.',
            b'LOCAL_SYNC_COLLECTOR_KEYS and a non-empty LOCAL_SYNC_ADMIN_KEY.')
    elif new_check in old_source:
        new_source = old_source
    else:
        raise SystemExit('The server validation changed since inspection. Nothing changed.')
    # Quoting is compatible with both systemd EnvironmentFile and Bash maintenance tools.
    quoted = '"' + ''.join('\\' + c if c in '\\"$`' else c for c in password) + '"'
    new_env, count = re.subn(rb'(?m)^LOCAL_SYNC_ADMIN_KEY=[^\r\n]*', lambda _: ('LOCAL_SYNC_ADMIN_KEY=' + quoted).encode('utf-8'), old_env)
    if count != 1:
        raise SystemExit('Expected one admin credential assignment. Nothing changed.')
    changed = False
    try:
        if ENV.read_bytes() != old_env or SOURCE.read_bytes() != old_source:
            raise RuntimeError('Concurrent configuration change')
        changed = True
        atomic_write(SOURCE, new_source, source_metadata)
        atomic_write(ENV, new_env, env_metadata)
        subprocess.run(['systemctl', 'restart', 'plus5-vps'], check=True, capture_output=True)
        ready = False
        for _ in range(30):
            try:
                code, current_health = health(password)
                if code == 200:
                    ready = True
                    break
            except (OSError, ValueError):
                pass
            time.sleep(1)
        if not ready or current_health.get('records') != previous_health.get('records'):
            raise RuntimeError('New-password health check failed')
        if health(old_password)[0] != 401:
            raise RuntimeError('Previous password was not revoked')
        after = environment()
        if after.get('LOCAL_SYNC_COLLECTOR_KEYS', '') != collectors:
            raise RuntimeError('Collector credentials changed unexpectedly')
        save_status(True, 'Admin password changed; new login verified, old password revoked, collector keys preserved.')
        print('Vivayu dashboard password changed successfully.')
        print('The new password was verified and the old password no longer works.')
        print('Open https://admin.nutrition.achantalabs.com/ and sign in again.')
    except BaseException:
        if changed:
            atomic_write(ENV, old_env, env_metadata)
            atomic_write(SOURCE, old_source, source_metadata)
            subprocess.run(['systemctl', 'restart', 'plus5-vps'], check=False, capture_output=True)
        save_status(False, 'Change did not complete; previous configuration restored.')
        raise SystemExit('The change did not complete. The previous password and configuration were restored.')


if __name__ == '__main__':
    main()
