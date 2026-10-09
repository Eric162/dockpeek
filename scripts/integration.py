#!/usr/bin/env python3
"""Exercise packaged settings, worker, and probe in marked temporary storage."""
import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
import uuid
from pathlib import Path


def wait_for(predicate, description, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out: {description}")


def atomic(path, text):
    temporary = path.with_suffix('.new')
    temporary.write_text(text)
    temporary.replace(path)


def snapshot(badge):
    return ("    ELEMENT\n    AXTitle=TextEdit\n"
            "    AXURL=file:///System/Applications/TextEdit.app/\n"
            "    AXFrame=value = x:600 y:99999 w:67 h:83\n"
            f"    AXStatusLabel={badge}\n")


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def run(app):
    settings = app / 'Contents/MacOS/DockPeekSettings'
    worker = app / 'Contents/Library/LoginItems/DockPeekWorker.app/Contents/MacOS/DockPeekWorker'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    checks = []
    for login_start in [False, True]:
        with tempfile.TemporaryDirectory(prefix='dockpeek-integration-') as directory:
            root = Path(directory)
            (root / '.dockpeek-verification').touch()
            atomic(root / 'snapshot.txt', snapshot('3'))
            atomic(root / 'peek-config.json', json.dumps({
                'allowedApps': ['com.apple.TextEdit'], 'entryAnimation': 'none',
                'dismissAnimation': 'none', 'openAppOnClick': False,
            }))
            atomic(root / 'worker.pid', '2147483647')
            arguments = [str(settings), '--verify-root', str(root)]
            arguments += ['--login-start'] if login_start else ['--verify-quit-after', '2']
            pid = None
            with (root / 'settings.log').open('w') as output:
                process = subprocess.Popen(arguments, stdout=output, stderr=output)
                try:
                    wait_for(lambda: (root / 'worker.pid').exists()
                             and (root / 'worker.pid').read_text().strip() != '2147483647', 'worker startup')
                    pid = int((root / 'worker.pid').read_text())
                    process.wait(timeout=15)
                    assert process.returncode == 0, (root / 'settings.log').read_text()
                    assert alive(pid), 'Worker exited with settings'
                    log = root / 'overlay.log'
                    text = lambda: log.read_text() if log.exists() else ''
                    wait_for(lambda: 'SETTLED' in text(), 'synthetic badge rendered')
                    duplicate = subprocess.run([str(worker), '--verify-root', str(root)], timeout=5,
                                               capture_output=True, text=True)
                    assert duplicate.returncode == 0, duplicate.stderr
                    assert int((root / 'worker.pid').read_text()) == pid
                    checks += ['login-start' if login_start else 'settings-quit', 'duplicate-worker', 'stale-pid']
                    if not login_start:
                        verify_interactions(root, text)
                        checks += ['right-click', 'scroll', 'badge-change', 'dock-return',
                                   'probe-failure', 'probe-timeout', 'invalid-config', 'recovery']
                    os.kill(pid, signal.SIGTERM)
                    wait_for(lambda: not alive(pid), 'worker drained shutdown')
                    assert 'STOPPED worker; probe drained' in text()
                    checks.append('graceful-shutdown')
                except Exception:
                    print((root / 'settings.log').read_text())
                    if (root / 'overlay.log').exists():
                        print((root / 'overlay.log').read_text())
                    raise
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)
                    if pid and alive(pid):
                        os.kill(pid, signal.SIGTERM)
                        try:
                            wait_for(lambda: not alive(pid), 'cleanup', timeout=5)
                        except AssertionError:
                            os.kill(pid, signal.SIGKILL)
                            raise
    return checks


def verify_interactions(root, text):
    def command(**values):
        atomic(root / 'command.json', json.dumps({'token': str(uuid.uuid4()), **values}))
    command(dockVisibility='hidden', dismiss='rightClick')
    wait_for(lambda: 'RIGHT-CLICK-DISMISS' in text() and 'HIDDEN' in text(), 'right click dismissed')
    entered = text().count('ENTER')
    time.sleep(2.2)
    assert text().count('ENTER') == entered, 'Unchanged badge reappeared'
    atomic(root / 'snapshot.txt', snapshot('8'))
    wait_for(lambda: 'BADGE com.apple.TextEdit=8' in text(), 'changed badge returned')
    command(dockVisibility='hidden', dismiss='scroll')
    wait_for(lambda: 'SCROLL-DISMISS' in text(), 'scroll dismissed')
    atomic(root / 'snapshot.txt', snapshot('9'))
    wait_for(lambda: 'BADGE com.apple.TextEdit=9' in text(), 'next badge')
    hidden = text().count('HIDDEN')
    command(dockVisibility='visible')
    wait_for(lambda: text().count('HIDDEN') > hidden, 'Dock reveal hides overlay')
    command(dockVisibility='hidden')
    wait_for(lambda: 'style=slide' in text(), 'Dock return slides')
    atomic(root / 'probe-mode', 'fail')
    wait_for(lambda: 'PROBE-FAILED exit(3)' in text(), 'probe failure')
    entered = text().count('ENTER')
    atomic(root / 'probe-mode', 'normal')
    wait_for(lambda: text().count('ENTER') > entered, 'probe recovery')
    atomic(root / 'probe-mode', 'hang')
    wait_for(lambda: 'PROBE-FAILED timedOut' in text(), 'probe timeout', timeout=10)
    entered = text().count('ENTER')
    atomic(root / 'probe-mode', 'normal')
    wait_for(lambda: text().count('ENTER') > entered, 'timeout recovery')
    hidden = text().count('HIDDEN')
    atomic(root / 'peek-config.json', '{invalid')
    wait_for(lambda: text().count('HIDDEN') > hidden, 'invalid configuration hides overlays')
    entered = text().count('ENTER')
    atomic(root / 'peek-config.json', json.dumps({'allowedApps': ['com.apple.TextEdit'], 'entryAnimation': 'none'}))
    wait_for(lambda: text().count('ENTER') > entered, 'valid configuration restores overlays')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('dist/Dock Peek.app'))
    args = parser.parse_args()
    checks = run(args.app.resolve())
    report = {'synthetic': True, 'app': str(args.app.resolve()), 'checks': checks,
              'limitations': ['No physical input, Accessibility permission, or actual logout/login cycle verified.']}
    target = Path('.build/reports/integration.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(f"Packaged integration passed: {len(checks)} assertions. Report: {target}")


if __name__ == '__main__':
    main()
