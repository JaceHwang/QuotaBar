#!/usr/bin/env python3
"""Launch the packaged App with an isolated home and no build-tree resource fallback."""
import argparse
import os
import pathlib
import plistlib
import signal
import subprocess
import tempfile
import time
import uuid


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def owned_processes(app):
    prefix = str(app.resolve() / 'Contents') + '/'
    rows = subprocess.check_output(['ps', '-axo', 'pid,stat,comm'], text=True).splitlines()
    return {int(parts[0]): '/Contents/MacOS/' in parts[2] for row in rows
            if len(parts := row.strip().split(None, 2)) == 3 and not parts[1].startswith('Z')
            and parts[2].startswith(prefix)}


def stop_owned(app, grace=10):
    processes = owned_processes(app)
    parents = [pid for pid, parent in processes.items() if parent]
    for pid in parents or processes:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline and owned_processes(app):
        time.sleep(.1)
    for pid in owned_processes(app):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and owned_processes(app):
        time.sleep(.1)
    assert not owned_processes(app), 'App-owned processes remained after cleanup'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path)
    parser.add_argument('--build-root', type=pathlib.Path)
    args = parser.parse_args()
    source = args.app.resolve()
    with (source / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    assert info['CUSStandalone'] is True
    for name in ('quota-icon-light.png', 'quota-icon-dark.png'):
        matches = list((source / 'Contents/Resources/CodexQuota_CodexQuota.bundle').rglob(name))
        assert len(matches) == 1 and matches[0].read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), name
    build = args.build_root.resolve() if args.build_root else None
    hidden = build.with_name('.build-hidden-' + uuid.uuid4().hex) if build and build.exists() else None
    if hidden:
        build.rename(hidden)
    try:
        with tempfile.TemporaryDirectory(prefix='quotabar-app-smoke-') as temporary:
            root = pathlib.Path(temporary).resolve()
            app = root / 'QuotaBar.app'
            home = root / 'home'
            home.mkdir()
            subprocess.run(['ditto', str(source), str(app)], check=True)
            stderr = root / 'stderr.txt'
            launcher = subprocess.Popen(['open', '-n', '-g', '-W', '--env', 'CFFIXED_USER_HOME=' + str(home),
                                         '--stdout', str(root / 'stdout.txt'), '--stderr', str(stderr), str(app)])
            pid = None
            children = []
            try:
                diagnostic = home / 'Library/Application Support/CodexUsageSidebar/standalone-state.txt'
                deadline = time.monotonic() + 45
                fields = {}
                while time.monotonic() < deadline:
                    if launcher.poll() is not None:
                        raise RuntimeError('Packaged App exited during startup: ' + (stderr.read_text() if stderr.exists() else 'no stderr'))
                    try:
                        fields = dict(item.split('=', 1) for item in diagnostic.read_text().split())
                        pid = int(fields['pid'])
                        if fields.get('phase') == 'needsLogin':
                            break
                    except (OSError, ValueError, KeyError):
                        pass
                    time.sleep(.2)
                assert fields.get('phase') == 'needsLogin' and pid and alive(pid), 'No ready isolated runtime: ' + str(fields)
                rows = subprocess.check_output(['ps', '-axo', 'pid,ppid,comm'], text=True).splitlines()
                children = [int(parts[0]) for row in rows if len(parts := row.strip().split(None, 2)) == 3
                            and parts[1] == str(pid) and parts[2].startswith(str(app / 'Contents/Helpers') + '/')]
                assert children, 'No owned official runtime process'
                os.kill(pid, signal.SIGTERM)
                assert launcher.wait(timeout=12) == 0, 'Application did not exit normally'
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and any(alive(child) for child in children):
                    time.sleep(.1)
                assert not alive(pid) and not any(alive(child) for child in children), 'Owned process remained after shutdown'
                print('PASS packaged macOS App startup, isolated account, official runtime and graceful exit without build resources')
            finally:
                try:
                    # LaunchServices can start the App before its first diagnostic.
                    # Find ownership from the unique copied bundle, even if open exited.
                    stop_owned(app)
                finally:
                    if launcher.poll() is None:
                        try:
                            launcher.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            launcher.terminate()
                            launcher.wait(timeout=5)
    finally:
        if hidden:
            hidden.rename(build)


if __name__ == '__main__':
    main()
