#!/usr/bin/env python3
"""Measure isolated release workers with macOS time, ps, sample, and leaks."""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from integration import alive, atomic, snapshot, wait_for


def measure(app, scenario, seconds, output, inspect, plugin=None):
    worker = app / 'Contents/Library/LoginItems/DockPeekWorker.app/Contents/MacOS/DockPeekWorker'
    probe = app / 'Contents/Resources/Dock Tile Probe.app'
    with tempfile.TemporaryDirectory(prefix='dockpeek-performance-') as directory:
        root = Path(directory)
        (root / '.dockpeek-verification').touch()
        (root / '.build').mkdir()
        shutil.copytree(probe, root / '.build/Dock Tile Probe.app')
        atomic(root / 'snapshot.txt', snapshot('3'))
        atomic(root / 'command.json', json.dumps({'token': 'performance', 'frontmostBundle': ''}))
        config = {
            'enabled': scenario != 'idle', 'allowedApps': ['com.apple.TextEdit'],
            'entryAnimation': 'none', 'dismissAnimation': 'none', 'openAppOnClick': False,
        }
        if plugin:
            manifest = json.loads(plugin.read_text())
            animations = root / 'Animations'
            animations.mkdir()
            shutil.copyfile(plugin, animations / 'plugin.json')
            descriptor = manifest['descriptor']
            for stage, key in [('entry', 'entryAnimation'), ('dismissal', 'dismissAnimation')]:
                if stage in descriptor['stages']:
                    config[key] = descriptor['id']
        atomic(root / 'peek-config.json', json.dumps(config))
        timer_path = output / f'{scenario}-time.txt'
        log = output / f'{scenario}-launch.txt'
        pid = None
        rss = []
        with timer_path.open('w') as timing, log.open('w') as stdout:
            process = subprocess.Popen(['/usr/bin/time', '-l', str(worker), '--verify-root', str(root)],
                                       stdout=stdout, stderr=timing)
            try:
                wait_for(lambda: (root / 'worker.pid').exists(), 'profile worker startup')
                pid = int((root / 'worker.pid').read_text())
                time.sleep(3)
                if inspect:
                    subprocess.run(['sample', str(pid), '2', '-file', str(output / f'{scenario}-sample.txt')],
                                   capture_output=True, timeout=10)
                    result = subprocess.run(['leaks', '--quiet', str(pid)], capture_output=True, text=True, timeout=20)
                    (output / f'{scenario}-leaks.txt').write_text(result.stdout + result.stderr)
                end = time.monotonic() + seconds
                while time.monotonic() < end:
                    value = subprocess.check_output(['ps', '-p', str(pid), '-o', 'rss='], text=True).strip()
                    rss.append(int(value))
                    if scenario == 'churn':
                        atomic(root / 'snapshot.txt', snapshot(str(len(rss))))
                    time.sleep(0.5)
                os.kill(pid, signal.SIGTERM)
                process.wait(timeout=10)
                assert process.returncode == 0, timer_path.read_text()
                diagnostics = json.loads((root / 'diagnostics.json').read_text())
                (output / f'{scenario}-worker.log').write_text((root / 'overlay.log').read_text())
                assert 'STOPPED worker; probe drained' in (root / 'overlay.log').read_text()
            finally:
                if pid and alive(pid):
                    os.kill(pid, signal.SIGKILL)
                if process.poll() is None:
                    process.wait(timeout=5)
        text = timer_path.read_text()
        timing = re.search(r'([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys', text)
        assert timing, text
        wall, user, system = map(float, timing.groups())
        peak = re.search(r'(\d+)\s+maximum resident set size', text)
        footprint = re.search(r'(\d+)\s+peak memory footprint', text)
        return {'scenario': scenario, 'wall_seconds': wall, 'cpu_seconds': user + system,
                'cpu_percent': round(100 * (user + system) / wall, 3),
                'rss_min_kib': min(rss), 'rss_max_kib': max(rss),
                'max_rss_bytes': int(peak.group(1)),
                'peak_footprint_bytes': int(footprint.group(1)) if footprint else None,
                'diagnostics': diagnostics}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path('dist/Dock Peek.app'))
    parser.add_argument('--seconds', type=float, default=12)
    parser.add_argument('--output', type=Path, default=Path('Artifacts/Performance/current'))
    parser.add_argument('--plugin', type=Path, help='Install this JSON animation in every isolated worker')
    parser.add_argument('--inspect', action='store_true', help='Also collect sample and leaks evidence')
    parser.add_argument('--gate', action='store_true', help='Check broad CPU/RSS and idle timer budgets')
    args = parser.parse_args()
    if not 3 <= args.seconds <= 300:
        parser.error('--seconds must be between 3 and 300')
    args.output.mkdir(parents=True, exist_ok=True)
    results = [measure(args.app.resolve(), scenario, args.seconds, args.output.resolve(), args.inspect, args.plugin)
               for scenario in ['idle', 'settled', 'churn']]
    report = {'synthetic': True, 'measurement': '/usr/bin/time -l includes startup and drain; ps samples follow 3s warmup',
              'plugin': str(args.plugin) if args.plugin else None,
              'host': subprocess.check_output(['sw_vers'], text=True).strip(), 'results': results}
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if args.gate:
        for result in results:
            assert result['cpu_percent'] < 10, f"CPU budget exceeded: {result}"
            assert result['rss_max_kib'] < 150 * 1024, f"RSS budget exceeded: {result}"
        assert results[0]['diagnostics']['animationTicks'] == 0, 'Idle animation timer fired'
        for result in results[1:]:
            assert result['diagnostics']['animationTimerActive'] == 0, 'Settled timer remained active'
            assert result['diagnostics']['iconLoads'] == 1, 'Unchanged icon reloaded'
            ticks = result['diagnostics']['animationTicks']
            if args.plugin:
                assert 0 < ticks <= 960, 'Plugin did not animate or continued beyond its budget'
            else:
                assert ticks <= 2, 'Settled animation timer fired repeatedly'


if __name__ == '__main__':
    main()
