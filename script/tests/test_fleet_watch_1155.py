import importlib.util
import os
import unittest
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location('fleet_watch', Path(__file__).parent.parent / 'fleet-watch.py')
fw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fw)

CONFIG = {'host_caps': {'local': 5, 'niteking': 5, 'blueDevil': 5}}


def settled_row(i):
    """Flat worker-list row: succeeded, terminal still retained, no resource, no worktree on disk."""
    return {
        'dispatchId': 'ctx_settled_%d' % i, 'taskId': 'task_s%d' % i,
        'state': 'succeeded', 'liveness': 'unverifiable', 'terminalState': 'retained',
        'workspace': 'repo::/nonexistent/settled-%d' % i, 'host': 'local',
    }


def live_row():
    return {
        'dispatchId': 'ctx_live', 'taskId': 'task_live',
        'state': 'ready', 'outcome': 'in_progress', 'liveness': 'live', 'terminalState': 'retained',
        'workspace': 'repo::/nonexistent/live', 'host': 'local',
    }


class SettledRowsHoldNoSeat(unittest.TestCase):
    def setUp(self):
        env = patch.dict(os.environ, {
            'FLEET_WATCH_TEST_LOAD_PER_CORE': '0.10',
            'FLEET_WATCH_TEST_FREE_GB': '16.0',
        })
        env.start()
        self.addCleanup(env.stop)

    def test_34_settled_plus_1_live_is_admitted_under_cap_5(self):
        workers = [settled_row(i) for i in range(34)] + [live_row()]
        receipt = fw.admit('local', CONFIG, workers=workers)
        self.assertTrue(receipt['admitted'], receipt['reason'])
        self.assertEqual(receipt['occupied'], 1)
        self.assertEqual(receipt['live_count'], 1)

    def test_full_local_overflows_to_first_admitted_remote(self):
        live = []
        for i in range(5):
            row = live_row()
            row['dispatchId'] = 'ctx_live_%d' % i
            row['taskId'] = 'task_live_%d' % i
            live.append(row)
        workers = [settled_row(i) for i in range(34)] + live
        receipt = fw.admit('local', CONFIG, workers=workers)
        self.assertFalse(receipt['admitted'])
        self.assertEqual(receipt['occupied'], 5)
        self.assertEqual(receipt['overflow_host'], 'niteking')


if __name__ == '__main__':
    unittest.main()
