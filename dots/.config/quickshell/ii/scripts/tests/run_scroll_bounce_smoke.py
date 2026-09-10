"""Exercise the real StyledFlickable/StyledListView overscroll bounce in Qt offscreen.

Only platform services and decorative widgets are replaced. No Quickshell
instance, compositor calls, screen capture or user config writes.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    runner = next((str(p) for p in (
        Path('/usr/lib64/qt6/bin/qmltestrunner'),
        Path('/usr/lib/qt6/bin/qmltestrunner'),
    ) if p.exists()), None) or shutil.which('qmltestrunner6')
    if not runner:
        raise SystemExit('Qt 6 qmltestrunner is required')

    with tempfile.TemporaryDirectory(prefix='ii-scroll-bounce-') as directory:
        out = Path(directory)

        def put(name, text):
            path = out / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

        put('qs/modules/common/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property QtObject options: QtObject {
        property QtObject appearance: QtObject {
            property bool settingsPerformanceMode: false
        }
        property QtObject interactions: QtObject {
            property QtObject scrolling: QtObject {
                property real touchpadScrollFactor: 100
                property real mouseScrollFactor: 50
                property real mouseScrollDeltaThreshold: 120
            }
        }
    }
}
''')
        put('qs/modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
    property real animMultiplier: 1.0
    property var animationCurves: ({expressiveDefaultSpatial: [0.4, 0, 0.2, 1]})
    property QtObject animation: QtObject {
        property QtObject scroll: QtObject {
            property int duration: 10
            property int type: Easing.OutCubic
            property var bezierCurve: [0.4, 0, 0.2, 1]
        }
        property QtObject elementMoveEnter: QtObject {
            property int duration: 10
            property int type: Easing.OutCubic
            property var bezierCurve: [0.4, 0, 0.2, 1]
        }
    }
}
''')
        put('qs/modules/common/widgets/StyledScrollBar.qml',
            'import QtQuick\nimport QtQuick.Controls\nScrollBar {}')
        for name in ('StyledFlickable', 'StyledListView'):
            put(f'qs/modules/common/widgets/{name}.qml',
                (ROOT / f'modules/common/widgets/{name}.qml').read_text())
        put('tests/tst_ScrollBounce.qml', (ROOT / 'tests/scroll/tst_ScrollBounce.qml').read_text())
        for folder in sorted((out / 'qs').rglob('*')):
            if not folder.is_dir():
                continue
            entries = []
            for qml in sorted(folder.glob('*.qml')):
                singleton = 'singleton ' if 'pragma Singleton' in qml.read_text() else ''
                entries.append(f'{singleton}{qml.stem} 1.0 {qml.name}')
            if entries:
                put(str(folder.relative_to(out) / 'qmldir'), '\n'.join(entries) + '\n')
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen',
                   QT_QUICK_BACKEND='software', QT_QUICK_CONTROLS_STYLE='Basic')
        result = subprocess.run([runner, '-input', str(out / 'tests'),
                                 '-import', str(out)],
                                env=env, capture_output=True, text=True, timeout=60)
        print(result.stdout, end='')
        print(result.stderr, end='')
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
