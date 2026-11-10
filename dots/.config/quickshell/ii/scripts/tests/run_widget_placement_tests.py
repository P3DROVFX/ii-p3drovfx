"""Run widget placement regressions without starting a shell or reading user config."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    runner = shutil.which('qmltestrunner6') or next((str(p) for p in (
        Path('/usr/lib64/qt6/bin/qmltestrunner'),
        Path('/usr/lib/qt6/bin/qmltestrunner'),
    ) if p.exists()), None) or shutil.which('qmltestrunner')
    if not runner:
        raise SystemExit('Qt 6 qmltestrunner is required')
    with tempfile.TemporaryDirectory(prefix='ii-widget-placement-') as directory:
        out = Path(directory)
        module = out / 'qs/modules/common/functions'
        module.mkdir(parents=True)
        # Quickshell's plugin is executable-only. Substitute its object base,
        # as in run_widget_tint_smoke.py; all placement functions stay unchanged.
        source = (ROOT / 'modules/common/functions/WidgetPlacement.qml').read_text()
        source = source.replace('import Quickshell\n', 'import QtQuick\n').replace('Singleton {', 'QtObject {')
        (module / 'WidgetPlacement.qml').write_text(source)
        (module / 'qmldir').write_text(
            'module qs.modules.common.functions\nsingleton WidgetPlacement 1.0 WidgetPlacement.qml\n'
        )
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        result = subprocess.run([
            runner, '-input', str(ROOT / 'tests/background/tst_WidgetPlacement.qml'),
            '-import', str(out),
        ], env=env, timeout=30)
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
