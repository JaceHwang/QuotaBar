#!/usr/bin/env python3
"""Reversible per-user installation of a verified local standalone candidate."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import tempfile
import time


def run(*args):
    subprocess.run(args, check=True)


def set_plugin_enabled(path, enabled):
    """Change only the existing legacy plugin flag; retain unrelated configuration."""
    if not path.exists():
        return None
    content = path.read_text()
    section = re.search(r'(?m)^\s*\[plugins\."codex-usage-sidebar@codex-usage-sidebar"\][^\n]*\n(?:(?![ \t]*\[).*(?:\n|$))*', content)
    if not section:
        return None
    flag = re.search(r'(?m)^(\s*enabled\s*=\s*)(true|false)\b', section.group())
    if not flag:
        raise RuntimeError('Legacy plugin has no explicit enabled flag; configuration unchanged')
    previous = flag.group(2) == 'true'
    if enabled is None:
        return previous
    start = section.start() + flag.start(2)
    end = section.start() + flag.end(2)
    replacement = content[:start] + ('true' if enabled else 'false') + content[end:]
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(replacement)
    os.chmod(temporary, path.stat().st_mode & 0o777)
    temporary.replace(path)
    return previous


def restore_legacy(home, info):
    legacy = info.get('legacy', {})
    flag = legacy.get('pluginEnabled')
    if flag is not None:
        set_plugin_enabled(home / '.codex/config.toml', flag)
    backup = Path(legacy['plistBackup']) if legacy.get('plistBackup') else None
    plist = home / 'Library/LaunchAgents/com.jace.codex-usage-sidebar.plist'
    if backup and backup.exists():
        if not plist.exists():
            run('ditto', str(backup), str(plist))
        elif plist.read_bytes() != backup.read_bytes():
            raise RuntimeError('Legacy launch agent destination conflicts with backup')
    if plist.exists():
        service = subprocess.run(['launchctl', 'print', f'gui/{os.getuid()}/com.jace.codex-usage-sidebar'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if service.returncode != 0:
            run('launchctl', 'bootstrap', f'gui/{os.getuid()}', str(plist))


def suspend_legacy(plist):
    label = f'gui/{os.getuid()}/com.jace.codex-usage-sidebar'
    subprocess.run(['launchctl', 'bootout', label], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        check = subprocess.run(['launchctl', 'print', label], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if check.returncode != 0:
            break
        time.sleep(.1)
    if check.returncode == 0:
        raise RuntimeError('Legacy service is still running; installation aborted')
    info = plistlib.loads(plist.read_bytes())
    program = info.get('Program') or info.get('ProgramArguments', [''])[0]
    if '.app/Contents/' in program:
        stop(Path(program.split('.app/Contents/')[0] + '.app'))


def stop(target):
    rows = subprocess.check_output(['ps', '-axo', 'pid,comm'], text=True).splitlines()
    owned = []
    parents = []
    for row in rows:
        fields = row.strip().split(None, 1)
        if len(fields) == 2 and fields[1].startswith(str(target / 'Contents') + '/'):
            owned.append(int(fields[0]))
            if '/Contents/MacOS/' in fields[1]:
                parents.append(int(fields[0]))
    # Parent handles orderly shutdown. Exact app-owned helpers are stopped as fallback.
    for pid in parents or owned:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _ in range(200):
        alive = []
        for pid in owned:
            try:
                os.kill(pid, 0)
                alive.append(pid)
            except ProcessLookupError:
                pass
        if not alive:
            return
        if parents and not any(pid in alive for pid in parents):
            for pid in alive:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        time.sleep(.05)
    raise RuntimeError('Application did not stop; installation left unchanged')


def application_executable(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        name = plistlib.load(stream)['CFBundleExecutable']
    if name not in {'CodexQuota', 'CodexUsageSidebar'}:
        raise RuntimeError('Unexpected application executable')
    return app / 'Contents/MacOS' / name


def verify(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleIdentifier') != 'com.jace.codex-quota' or info.get('CUSStandalone') is not True:
        raise RuntimeError('Not a standalone Codex Quota bundle')
    run('codesign', '--verify', '--deep', '--strict', str(app))
    version = subprocess.check_output([str(app / 'Contents/Helpers/codex'), '--version'], text=True).strip()
    if version != 'codex-cli 0.144.1':
        raise RuntimeError('Unexpected runtime version')


def atomic_json(path, value):
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(value, stream, indent=2)
        stream.write('\n')
    temporary.replace(path)


def recover_install(home, info, marker, record, backups, reopen=True):
    target = Path(info['target'])
    original_target = Path(info.get('originalTarget', info['target']))
    previous = Path(info['previous']) if info.get('previous') else None
    if previous and previous.exists():
        if target.exists():
            stop(target)
            if info.get('originalTarget') and info.get('startupEnabled'):
                run(str(application_executable(target)), '--unregister-startup')
            replacement = Path(info['replacementSource']) if info.get('replacementSource') else backups / ('failed-' + str(time.time_ns()) + '.app')
            target.rename(replacement)
        previous.rename(original_target)
    elif previous is None and target.exists():
        stop(target)
        target.rename(backups / ('failed-' + str(time.time_ns()) + '.app'))
    if info.get('kind') == 'restore':
        plist = home / 'Library/LaunchAgents/com.jace.codex-usage-sidebar.plist'
        if plist.exists():
            suspend_legacy(plist)
            if not info.get('plistExisted'):
                plist.unlink()
        set_plugin_enabled(home / '.codex/config.toml', info.get('pluginEnabled', False))
        if info.get('startupEnabled') and target.exists():
            run(str(application_executable(target)), '--register-startup')
    else:
        restore_legacy(home, info)
    if info.get('oldMarker') is None:
        marker.unlink(missing_ok=True)
    else:
        marker.write_text(info['oldMarker'])
    if info.get('oldRecord'):
        atomic_json(record, info['oldRecord'])
    else:
        record.unlink(missing_ok=True)
    if info.get('startupEnabled') and info.get('originalTarget') and original_target.exists():
        run(str(application_executable(original_target)), '--register-startup')
    if reopen and original_target.exists():
        run('open', str(original_target))


def active_application(home):
    preferred = home / 'Applications/QuotaBar.app'
    legacy = home / 'Applications/Codex Quota.app'
    return preferred if preferred.exists() or not legacy.exists() else legacy


def startup_enabled(app):
    if not app.exists(): return False
    try:
        result = subprocess.run([str(application_executable(app)), '--startup-status'], capture_output=True, text=True)
        return result.returncode == 0 and result.stdout.strip() == '1'
    except (OSError, ValueError, KeyError):
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'rollback', 'uninstall'])
    parser.add_argument('--candidate', type=Path)
    args = parser.parse_args()
    home = Path.home()
    target = home / 'Applications/QuotaBar.app' if args.action == 'install' else active_application(home)
    root = home / 'Library/Application Support/CodexUsageSidebar'
    backups = root / '.StandaloneBackups'
    root.mkdir(parents=True, exist_ok=True)
    backups.mkdir(exist_ok=True)
    marker = root / 'standalone-mode'
    record = root / 'standalone-install.json'
    journal = root / 'standalone-transaction.json'
    if journal.exists():
        recover_install(home, json.loads(journal.read_text()), marker, record, backups, reopen=False)
        journal.unlink()
        if args.action != 'install':
            target = active_application(home)
    if args.action == 'install':
        if args.candidate is None:
            parser.error('install requires --candidate APP')
        source = args.candidate.resolve()
        verify(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        old_record = json.loads(record.read_text()) if record.exists() else {}
        old_marker = marker.read_text() if marker.exists() else None
        legacy = old_record.get('legacy', {})
        original_target = active_application(home)
        if target.exists() and (home / 'Applications/Codex Quota.app').exists():
            raise RuntimeError('Both QuotaBar and Codex Quota bundles exist; resolve duplicate applications before installing')
        startup = startup_enabled(original_target)
        previous = backups / (str(time.time_ns()) + '.app') if original_target.exists() else None
        plist = home / 'Library/LaunchAgents/com.jace.codex-usage-sidebar.plist'
        legacy_backup = backups / ('legacy-' + str(time.time_ns()) + '.plist') if plist.exists() else None
        recovery = {'target': str(target), 'originalTarget': str(original_target), 'startupEnabled': startup, 'previous': str(previous) if previous else None, 'oldRecord': old_record, 'oldMarker': old_marker, 'legacy': {'pluginEnabled': set_plugin_enabled(home / '.codex/config.toml', None), 'plistBackup': str(legacy_backup) if legacy_backup else None}}
        atomic_json(journal, recovery)
        moved_legacy = False
        changed_flag = None
        installed = False
        with tempfile.TemporaryDirectory(prefix='.quota-install-', dir=target.parent) as temporary:
            staged = Path(temporary) / target.name
            run('ditto', str(source), str(staged))
            verify(staged)
            stop(original_target)
            try:
                if startup and original_target != target:
                    run(str(application_executable(original_target)), '--unregister-startup')
                config = home / '.codex/config.toml'
                changed_flag = set_plugin_enabled(config, False)
                if 'pluginEnabled' not in legacy:
                    legacy['pluginEnabled'] = changed_flag
                label = 'com.jace.codex-usage-sidebar'
                plist = home / 'Library/LaunchAgents' / (label + '.plist')
                if plist.exists():
                    backup = legacy_backup
                    legacy['plistBackup'] = str(backup)
                    # Persist recovery metadata before deactivating the legacy service.
                    record.write_text(json.dumps({'target': str(target), 'legacy': legacy, 'transaction': 'installing'}, indent=2) + '\n')
                    suspend_legacy(plist)
                    plist.rename(backup)
                    moved_legacy = True
                if original_target.exists():
                    original_target.rename(previous)
                staged.rename(target)
                installed = True
                marker.write_text('Independent Codex Quota owns the isolated account directory.\n')
                record.write_text(json.dumps({'target': str(target), 'previous': str(previous) if previous else None, 'legacy': legacy, 'credentialsPreserved': True}, indent=2) + '\n')
                if startup and original_target != target:
                    run(str(application_executable(target)), '--register-startup')
                run('open', str(target))
            except BaseException:
                recover_install(home, recovery, marker, record, backups)
                journal.unlink()
                raise
        journal.unlink()
        print('Installed verified standalone candidate; legacy entry disabled, backups and credentials preserved')
    elif args.action == 'rollback':
        info = json.loads(record.read_text())
        previous = Path(info['previous']) if info.get('previous') else None
        if previous is None or previous.parent != backups or not previous.exists():
            raise RuntimeError('No previous standalone application available')
        verify(previous)
        stop(target)
        replaced = backups / (str(time.time_ns()) + '.app')
        recovery = {'target': str(target), 'previous': str(replaced), 'replacementSource': str(previous), 'oldRecord': info, 'oldMarker': marker.read_text() if marker.exists() else None, 'legacy': {}}
        atomic_json(journal, recovery)
        try:
            target.rename(replaced)
            previous.rename(target)
            info = {**info, 'previous': str(replaced)}
            atomic_json(record, info)
            run('open', str(target))
        except BaseException:
            recover_install(home, recovery, marker, record, backups)
            journal.unlink()
            raise
        journal.unlink()
        print('Rolled back application; credentials preserved')
    else:
        stop(target)
        if target.exists():
            run(str(application_executable(target)), '--unregister-startup')
            target.rename(backups / ('uninstalled-' + str(time.time_ns()) + '.app'))
        marker.unlink(missing_ok=True)
        print('Uninstalled active application; recoverable backup and credentials preserved')


if __name__ == '__main__':
    main()
