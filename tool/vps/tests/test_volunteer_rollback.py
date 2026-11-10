"""Isolated rollback authorization checks; never touches the production state."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('volunteer_deploy', Path(__file__).parents[1] / 'deploy-volunteer-release.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class RollbackTests(unittest.TestCase):
    def test_only_volunteer_keys_are_disabled_before_legacy_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            deploy.STATE = Path(directory)
            registry = deploy.STATE / 'collector_accounts.json'
            staff = {'key': 'synthetic-staff', 'status': 'active'}
            registry.write_text(json.dumps({'C001': staff, 'C002': {
                'key': 'synthetic-volunteer', 'isVolunteer': True, 'status': 'active'}}))
            with patch.object(deploy.os, 'chown', create=True) as change_owner:
                deploy.disable_volunteers_for_legacy_rollback()
                change_owner.assert_called_once()
            actual = json.loads(registry.read_text())
            self.assertEqual(actual['C001'], staff)
            self.assertEqual(actual['C002']['status'], 'disabled')
            self.assertEqual(actual['C002']['key'], 'synthetic-volunteer')
            self.assertEqual(sorted(p.name for p in deploy.STATE.iterdir()), ['collector_accounts.json'])
            deploy.disable_volunteers_for_legacy_rollback()
            self.assertEqual(json.loads(registry.read_text()), actual)

    def test_missing_registry_is_not_created(self):
        with tempfile.TemporaryDirectory() as directory:
            deploy.STATE = Path(directory)
            deploy.disable_volunteers_for_legacy_rollback()
            self.assertEqual(list(deploy.STATE.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
