"""Restore local API forwarding when an authorized Android test phone reconnects."""
import argparse
import subprocess
import time


def adb_command(adb, *arguments):
    return subprocess.run(
        [adb, *arguments], capture_output=True, text=True, timeout=10,
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
    )


def restore_connections(adb, previous):
    listing = adb_command(adb, 'devices')
    if listing.returncode:
        return set()
    connected = {
        parts[0] for line in listing.stdout.splitlines()
        if len(parts := line.split()) >= 2 and parts[1] == 'device'
    }
    restored = connected & previous
    for serial in connected - previous:
        result = adb_command(adb, '-s', serial, 'reverse', 'tcp:8000', 'tcp:8000')
        if result.returncode == 0:
            restored.add(serial)
            print('USB backend connection restored for a test phone.', flush=True)
    return restored


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', required=True)
    args = parser.parse_args()
    previous = set()
    while True:
        try:
            previous = restore_connections(args.adb, previous)
        except (OSError, subprocess.TimeoutExpired):
            previous = set()
        time.sleep(3)


if __name__ == '__main__':
    main()
