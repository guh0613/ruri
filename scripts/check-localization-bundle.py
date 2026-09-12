#!/usr/bin/env python3
"""Check localization in relocated executable bundles without loading game data."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def check(app, cli=None):
    with tempfile.TemporaryDirectory(prefix='ruri-localization-') as directory:
        root = Path(directory)
        moved = root / 'Ruri.app'
        shutil.copytree(app, moved)
        binaries = [moved / 'Contents/MacOS/Ruri', moved / 'Contents/Helpers/ruri-monitor']
        if cli:
            standalone = root / 'bin'
            standalone.mkdir()
            shutil.copy2(cli, standalone / 'ruri-cli')
            for bundle in (moved / 'Contents/Resources').glob('*.bundle'):
                shutil.copytree(bundle, standalone / bundle.name)
            binaries.append(standalone / 'ruri-cli')
        environment = dict(os.environ, RURI_DATA_DIR=str(root / 'untouched-data'), RURI_LANGUAGE='unsupported-language')
        for binary in binaries:
            result = subprocess.run([str(binary), '--localization-check'], env=environment,
                                    check=True, capture_output=True, text=True, timeout=30)
            report = json.loads(result.stdout)
            if not Path(report['bundle']).resolve().is_relative_to(root.resolve()):
                raise RuntimeError(f'{binary.name} used resources outside the relocated package')
            if not report['message'] or 'zh-hans' not in [name.lower() for name in report['languages']]:
                raise RuntimeError(f'{binary.name} did not read the base localization')
            print(f'{binary.name}: relocated localization resources verified')
        if (root / 'untouched-data').exists():
            raise RuntimeError('Resource check unexpectedly initialized launcher data')
        # A missing installed bundle must fail the check, not use the build tree.
        shutil.rmtree(moved / 'Contents/Resources/Ruri_RuriLocalization.bundle')
        for binary in binaries[:2]:
            result = subprocess.run([str(binary), '--localization-check'], env=environment,
                                    capture_output=True, text=True, timeout=30)
            if result.returncode != 2:
                raise RuntimeError(f'{binary.name} failed to detect its missing resource bundle')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--cli', type=Path)
    args = parser.parse_args()
    check(args.app.resolve(), args.cli.resolve() if args.cli else None)
