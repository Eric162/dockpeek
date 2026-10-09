#!/usr/bin/env python3
"""Package SwiftPM executables as the settings, worker, and probe app bundles."""
import plistlib
import shutil
import sys
from pathlib import Path


def bundle(path, binary, identifier, name, background=False):
    macos = path / 'Contents/MacOS'
    macos.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, macos / binary.name)
    info = {
        'CFBundleIdentifier': identifier,
        'CFBundleExecutable': binary.name,
        'CFBundleName': name,
        'CFBundleDisplayName': name,
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '0.2.0',
        'CFBundleVersion': '3',
        'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True,
    }
    if background:
        info['LSUIElement'] = True
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))


def main():
    binaries = Path(sys.argv[1])
    app = Path('dist/Dock Peek.app')
    if app.exists():
        shutil.rmtree(app)
    bundle(app, binaries / 'DockPeekSettings', 'local.dock-peek.settings', 'Dock Peek')
    bundle(app / 'Contents/Library/LoginItems/DockPeekWorker.app',
           binaries / 'DockPeekWorker', 'local.dock-peek.worker', 'Dock Peek Worker', True)
    bundle(app / 'Contents/Resources/Dock Tile Probe.app',
           binaries / 'DockTileProbe', 'local.dock-tile-probe', 'Dock Tile Probe', True)
    # Keep the previous agent manifest available only for migration/unregistration.
    agents = app / 'Contents/Library/LaunchAgents'
    agents.mkdir(parents=True, exist_ok=True)
    agent = {
        'Label': 'local.dock-peek.worker',
        'BundleProgram': 'Contents/Library/LoginItems/DockPeekWorker.app/Contents/MacOS/DockPeekWorker',
        'ProgramArguments': ['DockPeekWorker', '--installed'],
        'AssociatedBundleIdentifiers': ['local.dock-peek.settings'],
    }
    (agents / 'local.dock-peek.worker.plist').write_bytes(plistlib.dumps(agent))


if __name__ == '__main__':
    main()
