"""Run separate production services, or supervise them on a single container host."""
import argparse
import signal
import subprocess
import sys
import time


COMMANDS = {
    'web': [sys.executable, '-m', 'gunicorn', '-c', 'gunicorn.conf.py', 'app:create_app()'],
    'realtime': [sys.executable, '-m', 'app.realtime_worker'],
    'companion': [sys.executable, '-m', 'app.companion_worker'],
}


def stop_children(children):
    for process in children:
        if process.poll() is None:
            process.terminate()
    deadline = time.monotonic() + 35
    for process in children:
        try:
            process.wait(timeout=max(0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def supervise(commands):
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    children = []
    try:
        for name, command in commands.items():
            children.append(subprocess.Popen(command))
            print(f'Started {name} service.', flush=True)
        while not stopping:
            if any(process.poll() is not None for process in children):
                print('A required service exited; restarting the container is required.', file=sys.stderr)
                return 1
            time.sleep(1)
        return 0
    finally:
        stop_children(children)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('service', choices=[*COMMANDS, 'all'], default='all', nargs='?')
    args = parser.parse_args()
    selected = COMMANDS if args.service == 'all' else {args.service: COMMANDS[args.service]}
    return supervise(selected)


if __name__ == '__main__':
    raise SystemExit(main())
