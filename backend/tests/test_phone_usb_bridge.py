import subprocess
import unittest
from unittest.mock import patch

from scripts.phone_usb_bridge import restore_connections


class PhoneUsbBridgeTests(unittest.TestCase):
    @patch('scripts.phone_usb_bridge.adb_command')
    def test_reconnecting_either_phone_restores_its_route(self, command):
        def run(adb, *arguments):
            if arguments == ('devices',):
                return subprocess.CompletedProcess([], 0, listing, '')
            return subprocess.CompletedProcess([], 0, '', '')

        command.side_effect = run
        listing = 'List of devices attached\npatient device\nguardian unauthorized\n'
        previous = restore_connections('adb', set())
        self.assertEqual(previous, {'patient'})
        listing = 'List of devices attached\nguardian device\n'
        previous = restore_connections('adb', previous)
        self.assertEqual(previous, {'guardian'})
        listing = 'List of devices attached\npatient device\nguardian device\n'
        self.assertEqual(restore_connections('adb', previous), {'patient', 'guardian'})
        reverse_calls = [c.args for c in command.call_args_list if '-s' in c.args]
        self.assertEqual(reverse_calls, [
            ('adb', '-s', 'patient', 'reverse', 'tcp:8000', 'tcp:8000'),
            ('adb', '-s', 'guardian', 'reverse', 'tcp:8000', 'tcp:8000'),
            ('adb', '-s', 'patient', 'reverse', 'tcp:8000', 'tcp:8000'),
        ])

    @patch('scripts.phone_usb_bridge.adb_command')
    def test_failed_forward_is_retried_without_touching_unauthorized_phones(self, command):
        listing = subprocess.CompletedProcess(
            [], 0, 'List of devices attached\npatient device\nguardian unauthorized\n', '',
        )
        command.side_effect = [listing, subprocess.CompletedProcess([], 1, '', 'offline')]
        previous = restore_connections('adb', set())
        self.assertEqual(previous, set())
        command.side_effect = [listing, subprocess.CompletedProcess([], 0, '', '')]
        self.assertEqual(restore_connections('adb', previous), {'patient'})
