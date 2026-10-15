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
    with tempfile.TemporaryDirectory(prefix='dockpeek-unmarked-') as directory:
        operator_pid = Path.home() / 'Library/Application Support/Dock Peek/worker.pid'
        before = operator_pid.read_bytes() if operator_pid.exists() else None
        live_pid = int(before) if before and before.strip().isdigit() and int(before) > 0 else None
        was_alive = live_pid and alive(live_pid)
        rejection = subprocess.run([str(worker), '--verify-root', directory], timeout=5,
                                   capture_output=True, text=True)
        assert rejection.returncode != 0, 'Worker accepted an unmarked verification root'
        assert 'Verification root must contain .dockpeek-verification' in rejection.stderr, rejection.stderr
        assert not list(Path(directory).iterdir()), 'Rejected root was modified'
        assert (operator_pid.read_bytes() if operator_pid.exists() else None) == before, 'Operator worker PID changed'
        assert not was_alive or alive(live_pid), 'Operator worker was stopped'
    checks = ['unmarked-root-rejection']
    for login_start in [False, True]:
        with tempfile.TemporaryDirectory(prefix='dockpeek-integration-') as directory:
            root = Path(directory)
            (root / '.dockpeek-verification').touch()
            atomic(root / 'snapshot.txt', snapshot('3'))
            atomic(root / 'peek-config.json', json.dumps({
                'allowedApps': ['com.apple.TextEdit'], 'entryAnimation': 'none',
                'dismissAnimation': 'none', 'openAppOnClick': False,
            }))
            atomic(root / 'command.json', json.dumps({'token': str(uuid.uuid4()), 'frontmostBundle': ''}))
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
                    checks += ['login-start' if login_start else 'settings-quit', 'stale-pid']
                    if not login_start:
                        duplicate = subprocess.run([str(worker), '--verify-root', str(root)], timeout=5,
                                                   capture_output=True, text=True)
                        assert duplicate.returncode == 0, duplicate.stderr
                        assert int((root / 'worker.pid').read_text()) == pid
                        checks.append('duplicate-worker')
                        verify_interactions(root, text)
                        checks += ['app-activation', 'app-switch', 'badge-update-while-active', 'active-app-preview',
                                   'right-click', 'scroll', 'badge-change', 'dock-return',
                                   'probe-failure', 'probe-timeout', 'invalid-config', 'recovery',
                                   'plugin-entry', 'plugin-dismissal', 'plugin-timer-stop',
                                   'plugin-removal', 'plugin-recovery', 'plugin-screen-top-entry']
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
        atomic(root / 'command.json', json.dumps({'token': str(uuid.uuid4()), 'frontmostBundle': '', **values}))
    def diagnostics():
        path = root / 'diagnostics.json'
        return json.loads(path.read_text()) if path.exists() else {}
    command(dockVisibility='hidden', frontmostBundle='com.apple.TextEdit')
    wait_for(lambda: diagnostics().get('visible') == 0, 'frontmost app hides its peek')
    reads = diagnostics()['probeReads']
    atomic(root / 'snapshot.txt', snapshot('4'))
    wait_for(lambda: diagnostics().get('probeReads', 0) > reads + 1, 'badge observed while active')
    assert diagnostics()['visible'] == 0, 'Active app peek reappeared on badge change'
    notifier = ('import Foundation\n'
                'DistributedNotificationCenter.default().postNotificationName('
                'Notification.Name("local.dock-peek.test-request"), '
                'object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)\n'
                'RunLoop.current.run(until: Date().addingTimeInterval(0.1))')
    notifier_source = root / 'notify-preview.swift'
    notifier_source.write_text(notifier)
    notifier_binary = root / 'notify-preview'
    subprocess.run(['swiftc', '-swift-version', '6', '-warnings-as-errors', str(notifier_source),
                    '-o', str(notifier_binary)], check=True, timeout=60)
    atomic(root / 'probe-mode', 'hang')
    time.sleep(1.1)
    saved = (root / 'peek-config.json').read_bytes()
    offset = len(text())
    preview = {
        'bundleIdentifier': 'com.apple.TextEdit',
        'applicationPath': '/System/Applications/TextEdit.app',
        'token': str(uuid.uuid4()), 'expiresAt': time.time() - 978307200 + 10,
        'configuration': {'entryAnimation': 'slide', 'dismissAnimation': 'none', 'peekFraction': 0.8,
                          'entrySettings': {'slide': {'duration': 0.15}}},
    }
    atomic(root / 'test-request.json', json.dumps(preview))
    subprocess.run([str(notifier_binary), str(root)], check=True, timeout=5)
    wait_for(lambda: diagnostics().get('visible') == 1,
             'test preview appears without waiting for the hanging probe', timeout=2)
    assert 'ENTER Dock Peek: TextEdit style=slide' in text()[offset:], 'Preview ignored draft entry'
    assert (root / 'peek-config.json').read_bytes() == saved, 'Preview saved draft settings'
    atomic(root / 'probe-mode', 'normal')
    command(dockVisibility='visible', frontmostBundle='com.apple.TextEdit')
    reads = diagnostics()['probeReads']
    wait_for(lambda: diagnostics().get('probeReads', 0) > reads + 1, 'preview observed with visible Dock')
    assert diagnostics()['visible'] == 1, 'Visible Dock suppressed the preview'
    offset = len(text())
    preview['token'] = str(uuid.uuid4())
    preview['configuration']['entryAnimation'] = 'none'
    atomic(root / 'test-request.json', json.dumps(preview))
    subprocess.run([str(notifier_binary), str(root)], check=True, timeout=5)
    wait_for(lambda: 'ENTER Dock Peek: TextEdit style=none' in text()[offset:], 'retest restarts with new draft')
    assert (root / 'peek-config.json').read_bytes() == saved, 'Retest saved draft settings'
    (root / 'test-request.json').unlink()
    wait_for(lambda: diagnostics().get('visible') == 0, 'ordinary active-app badge stays hidden after preview')
    command(dockVisibility='hidden', frontmostBundle='other.app')
    wait_for(lambda: 'BADGE com.apple.TextEdit=4' in text(), 'switching away restores latest badge')
    wait_for(lambda: diagnostics().get('visible') == 1, 'background app peek restored')
    command(dockVisibility='hidden', frontmostBundle='', dismiss='rightClick')
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
    offset = len(text())
    command(dockVisibility='hidden')
    wait_for(lambda: 'ENTER Dock Peek: TextEdit style=slide' in text()[offset:], 'Dock return slides')
    atomic(root / 'probe-mode', 'fail')
    wait_for(lambda: 'PROBE-FAILED exit(3)' in text(), 'probe failure')
    entered = text().count('ENTER')
    atomic(root / 'probe-mode', 'normal')
    wait_for(lambda: text().count('ENTER') > entered, 'probe recovery')
    offset = len(text())
    atomic(root / 'probe-mode', 'hang')
    wait_for(lambda: 'PROBE-FAILED timedOut' in text()[offset:], 'probe timeout', timeout=10)
    entered = text().count('ENTER')
    atomic(root / 'probe-mode', 'normal')
    wait_for(lambda: text().count('ENTER') > entered, 'timeout recovery')
    hidden = text().count('HIDDEN')
    atomic(root / 'peek-config.json', '{invalid')
    wait_for(lambda: text().count('HIDDEN') > hidden, 'invalid configuration hides overlays')
    entered = text().count('ENTER')
    atomic(root / 'peek-config.json', json.dumps({'allowedApps': ['com.apple.TextEdit'], 'entryAnimation': 'none'}))
    wait_for(lambda: text().count('ENTER') > entered, 'valid configuration restores overlays')

    animations = root / 'Animations'
    animations.mkdir()
    example = json.loads(Path('docs/examples/fade.json').read_text())
    atomic(animations / 'example.fade.json', json.dumps(example))
    config = {'allowedApps': ['com.apple.TextEdit'], 'entryAnimation': 'example.fade',
              'dismissAnimation': 'example.fade', 'openAppOnClick': False,
              'entrySettings': {'example.fade': {'duration': 0.4, 'lift': 16,
                                                'bounce': False, 'direction': 'down'}},
              'dismissalSettings': {'example.fade': {'duration': 0.2}}}
    atomic(root / 'snapshot.txt', snapshot(''))
    wait_for(lambda: diagnostics().get('visible') == 0, 'clear badge before plugin test')
    atomic(root / 'peek-config.json', json.dumps(config))
    atomic(root / 'snapshot.txt', snapshot('12'))
    settled = text().count('SETTLED')
    ticks = diagnostics().get('animationTicks', 0)
    wait_for(lambda: 'ENTER Dock Peek: TextEdit style=example.fade' in text(), 'external plugin entry')
    wait_for(lambda: text().count('SETTLED') > settled, 'external plugin settles')
    wait_for(lambda: diagnostics().get('animationTimerActive') == 0, 'plugin timer stops')
    assert diagnostics()['animationTicks'] > ticks, 'Plugin settled without animating'
    hidden = text().count('HIDDEN')
    command(dockVisibility='hidden', dismiss='rightClick')
    wait_for(lambda: 'EXIT Dock Peek: TextEdit style=example.fade' in text()
             and text().count('HIDDEN') > hidden, 'external plugin dismissal')
    (animations / 'example.fade.json').unlink()
    atomic(root / 'snapshot.txt', snapshot('13'))
    reads = diagnostics()['probeReads']
    time.sleep(2.2)
    assert diagnostics()['visible'] == 0, 'Missing selected plugin rendered'
    assert diagnostics()['probeReads'] == reads, 'Missing selected plugin kept probing'
    atomic(animations / 'example.fade.json', json.dumps(example))
    entered = text().count('ENTER')
    wait_for(lambda: text().count('ENTER') > entered, 'reinstalled plugin recovers')
    top = json.loads(json.dumps(example))
    top['descriptor'].update(id='example.top', name='Screen top', stages=['entry'])
    top['keyframes'][0].update(travel=1, y={'binding': 'screenTopOffset'})
    atomic(animations / 'example.top.json', json.dumps(top))
    atomic(root / 'snapshot.txt', snapshot(''))
    wait_for(lambda: diagnostics().get('visible') == 0, 'clear badge before screen-top entry')
    config.update(entryAnimation='example.top', dismissAnimation='slide')
    atomic(root / 'peek-config.json', json.dumps(config))
    settled = text().count('SETTLED')
    ticks = diagnostics()['animationTicks']
    atomic(root / 'snapshot.txt', snapshot('14'))
    wait_for(lambda: 'ENTER Dock Peek: TextEdit style=example.top' in text(), 'screen-top plugin enters')
    wait_for(lambda: text().count('SETTLED') > settled, 'screen-top plugin settles')
    wait_for(lambda: diagnostics().get('animationTimerActive') == 0, 'screen-top timer stops')
    assert diagnostics()['animationTicks'] > ticks, 'Screen-top animation did not run'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('dist/Dock Peek.app'))
    args = parser.parse_args()
    checks = run(args.app.resolve())
    report = {'synthetic': True, 'app': str(args.app.resolve()), 'checks': checks,
              'limitations': ['App focus and Dock snapshots are synthetic. No physical input, Accessibility permission, or actual logout/login cycle verified.']}
    target = Path('.build/reports/integration.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(f"Packaged integration passed: {len(checks)} assertions. Report: {target}")


if __name__ == '__main__':
    main()
