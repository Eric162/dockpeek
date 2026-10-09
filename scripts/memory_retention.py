#!/usr/bin/env python3
"""Create and remove 32 synthetic app peeks, checking retained renderer state."""
import json
import os
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from integration import alive, atomic, wait_for


def run(app, output):
    output.mkdir(parents=True, exist_ok=True)
    worker = app / 'Contents/Library/LoginItems/DockPeekWorker.app/Contents/MacOS/DockPeekWorker'
    with tempfile.TemporaryDirectory(prefix='dockpeek-retention-') as directory:
        root = Path(directory)
        (root / '.dockpeek-verification').touch()
        (root / '.build').mkdir()
        shutil.copytree(app / 'Contents/Resources/Dock Tile Probe.app', root / '.build/Dock Tile Probe.app')
        identifiers = []
        sections = []
        for index in range(32):
            fixture = root / f'Fixture-{index}.app'
            (fixture / 'Contents').mkdir(parents=True)
            identifier = f'local.dockpeek.fixture-{index}'
            identifiers.append(identifier)
            (fixture / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': identifier, 'CFBundleName': f'Fixture {index}',
                'CFBundlePackageType': 'APPL',
            }))
            sections.append(f'    ELEMENT\n    AXTitle=Fixture {index}\n    AXURL={fixture.as_uri()}/\n'
                            f'    AXFrame=value = x:{index * 20} y:99999 w:67 h:83\n    AXStatusLabel=3\n')
        atomic(root / 'snapshot.txt', ''.join(sections))
        atomic(root / 'peek-config.json', json.dumps({'allowedApps': identifiers,
               'entryAnimation': 'none', 'dismissAnimation': 'none'}))
        diagnostics = lambda: json.loads((root / 'diagnostics.json').read_text()) if (root / 'diagnostics.json').exists() else {}
        pid = None
        process = subprocess.Popen([str(worker), '--verify-root', str(root)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            wait_for(lambda: (root / 'worker.pid').exists(), 'retention worker startup')
            pid = int((root / 'worker.pid').read_text())
            wait_for(lambda: diagnostics().get('presentations') == 32, '32 retained peeks')
            wait_for(lambda: diagnostics().get('animationTimerActive') == 0, 'settled timer')
            cycles = []
            before = diagnostics()
            for cycle in range(5):
                atomic(root / 'snapshot.txt', ''.join(sections))
                wait_for(lambda: diagnostics().get('presentations') == 32, '32 peeks recreated')
                time.sleep(2)
                shown_rss = int(subprocess.check_output(['ps', '-p', str(pid), '-o', 'rss='], text=True).strip())
                atomic(root / 'snapshot.txt', 'No Dock tiles\n')
                wait_for(lambda: diagnostics().get('presentations') == 0, 'hidden panels released')
                time.sleep(3)
                after = diagnostics()
                hidden_rss = int(subprocess.check_output(['ps', '-p', str(pid), '-o', 'rss='], text=True).strip())
                assert after['visible'] == 0 and after['iconLoads'] == 0
                assert after['animationTimerActive'] == 0
                cycles.append({'cycle': cycle + 1, 'shown_rss_kib': shown_rss, 'hidden_rss_kib': hidden_rss})
            assert cycles[-1]['hidden_rss_kib'] - cycles[0]['hidden_rss_kib'] < 32 * 1024, cycles
            inspection = subprocess.run(['leaks', '--quiet', str(pid)], capture_output=True, text=True, timeout=20)
            (output / 'retention-leaks.txt').write_text(inspection.stdout + inspection.stderr)
            assert after['visible'] == 0 and after['iconLoads'] == 0
            assert after['animationTimerActive'] == 0
            report = {'synthetic': True, 'before': before, 'after': after,
                      'cycles': cycles,
                      'leaks_exit_code': inspection.returncode,
                      'note': 'RSS may stay allocated after objects are freed; renderer counts test ownership.'}
            (output / 'retention.json').write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(report, indent=2))
            os.kill(pid, signal.SIGTERM)
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                if pid and alive(pid):
                    os.kill(pid, signal.SIGKILL)
                process.wait(timeout=5)


if __name__ == '__main__':
    run(Path('dist/Dock Peek.app').resolve(), Path('Artifacts/Performance/after').resolve())
