"""Activate a pre-staged Vivayu release without exposing volunteer keys on rollback.

Run as root on the existing VPS, with the staged release ID as the only argument.
Never prints credentials or records; does not create accounts or synthetic data.
"""
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time
import urllib.request

ROOT = Path('/opt/plus5-vps')
STATE = Path('/var/lib/plus5-vps/state')
SERVICE = 'plus5-vps.service'


def replace_link(destination, target):
    temporary = destination.with_name(destination.name + '.volunteer-new')
    if temporary.is_symlink():
        temporary.unlink()
    temporary.symlink_to(target, target_is_directory=True)
    os.replace(temporary, destination)


def health(key):
    request = urllib.request.Request('http://127.0.0.1:8787/health', headers={
        'X-Forwarded-Proto': 'https', 'X-Local-Sync-Key': key,
    })
    with urllib.request.urlopen(request, timeout=3) as response:
        return json.load(response)


def disable_volunteers_for_legacy_rollback():
    registry = STATE / 'collector_accounts.json'
    if not registry.exists():
        return
    accounts = json.loads(registry.read_text())
    changed = False
    for account in accounts.values():
        if account.get('isVolunteer') is True and account.get('status') == 'active':
            account['status'] = 'disabled'
            changed = True
    if not changed:
        return
    metadata = registry.stat()
    temporary = registry.with_name('collector_accounts.volunteer-rollback.tmp')
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as handle:
        handle.write(json.dumps(accounts))
        handle.flush()
        os.fsync(handle.fileno())
    temporary.chmod(stat.S_IMODE(metadata.st_mode))
    os.chown(temporary, metadata.st_uid, metadata.st_gid)
    os.replace(temporary, registry)


def main():
    if os.geteuid() != 0 or len(sys.argv) != 2:
        raise SystemExit('Run as root with one staged release ID.')
    release_id = sys.argv[1]
    if not re.fullmatch(r'[a-zA-Z0-9._-]+', release_id):
        raise SystemExit('Invalid release ID.')
    release = ROOT / 'releases' / release_id
    current = ROOT / 'current'
    previous = current.resolve(strict=True)
    if previous.parent != ROOT / 'releases' or not (release / 'build/admin_web/index.html').is_file():
        raise SystemExit('Unexpected release layout.')
    config = {}
    for line in Path('/etc/plus5-vps/local-sync.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            name, value = line.split('=', 1)
            config[name.strip()] = value.strip().strip('\"\'')
    key = config['LOCAL_SYNC_ADMIN_KEY']
    before = health(key)
    backup = Path('/var/backups/plus5-vps') / ('before-' + release_id)
    backup.mkdir(mode=0o700, parents=True, exist_ok=False)
    # Records are not rewritten by deployment. Preserve credential/session state
    # privately in case later operator recovery is needed.
    for name in ['collector_accounts.json', 'collector_sessions.json']:
        source = STATE / name
        if source.exists():
            shutil.copy2(source, backup / name)
            (backup / name).chmod(0o600)
    try:
        replace_link(current, release)
        subprocess.run(['systemctl', 'restart', SERVICE], check=True)
        deadline = time.monotonic() + 35
        after = None
        while time.monotonic() < deadline:
            try:
                after = health(key)
                break
            except Exception:
                time.sleep(0.5)
        if after is None or after.get('records', -1) < before.get('records', 0):
            raise RuntimeError('New release failed health or record-preservation check.')
        replace_link(ROOT / 'previous', previous)
        print(json.dumps({'release': release_id, 'health': after['status'],
                          'records_before': before['records'], 'records_after': after['records']}))
    except Exception:
        subprocess.run(['systemctl', 'stop', SERVICE], check=True)
        # Old firmware does not know the restricted volunteer role. Fail closed:
        # disable its keys before ever starting the previous backend.
        disable_volunteers_for_legacy_rollback()
        replace_link(current, previous)
        subprocess.run(['systemctl', 'start', SERVICE], check=True)
        print('Deployment failed; previous release restored. Volunteer access disabled for safe legacy rollback.', file=sys.stderr)
        raise


if __name__ == '__main__':
    main()
