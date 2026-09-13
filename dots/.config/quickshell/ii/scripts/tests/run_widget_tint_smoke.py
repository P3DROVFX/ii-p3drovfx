"""Exercise real widget palette, paint bindings and Canvas updates in Qt offscreen.

Platform state and decorative chrome are substituted; no shell instance, IPC,
network, screenshots or user config writes. Run from any directory with Python 3.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = (
    'services/WidgetColorScheme.qml',
    'modules/common/functions/ColorUtils.qml',
    'modules/ii/background/widgets/utility/QuoteWidget.qml',
    'modules/ii/background/widgets/clock/MonthClock.qml',
    'modules/ii/background/widgets/clock/TripleRingClock.qml',
)


def main():
    runner = shutil.which('qmltestrunner6') or next((str(p) for p in (Path('/usr/lib64/qt6/bin/qmltestrunner'), Path('/usr/lib/qt6/bin/qmltestrunner')) if p.exists()), None) or shutil.which('qmltestrunner')
    if not runner:
        raise SystemExit('Qt 6 qmltestrunner is required')
    with tempfile.TemporaryDirectory(prefix='ii-widget-tint-') as directory:
        out = Path(directory)

        def put(name, content):
            path = out / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

        alltext = '\n'.join((ROOT / name).read_text() for name in SOURCES)
        for name in SOURCES:
            content = (ROOT / name).read_text().replace('import Quickshell\n', 'import QtQuick\n').replace('Singleton {', 'QtObject {').replace('import qs\n', '')
            if name.endswith('QuoteWidget.qml'):
                # Expose existing items for assertions without replacing their bindings.
                content = content.replace('id: bgRect', 'id: bgRect\n        objectName: "background"')
                content = content.replace('id: quoteText', 'id: quoteText\n            objectName: "quoteText"')
            put('qs/' + name, content)

        groups = []
        for group in ('colors', 'm3colors'):
            names = sorted(set(re.findall(r'Appearance\.' + group + r'\.(\w+)', alltext)))
            fields = '\n'.join(f'property color {name}: Qt.hsla({i / len(names)}, 0.5, 0.5, 1)' for i, name in enumerate(names))
            groups.append(f'property QtObject {group}: QtObject {{\n{fields}\n}}')
        put('qs/modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
%s
property var rounding: ({windowRounding: 20})
property var font: ({pixelSize: {normal:16}, family: {expressive:"sans-serif",title:"sans-serif"}})
}
''' % '\n'.join(groups))
        config = (ROOT / 'modules/common/Config.qml').read_text()
        defaults = '\n'.join(re.findall(r'property (?:bool tintOpacityEnabled|real tintOpacity): [^\n]+', config))
        put('qs/modules/common/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
property bool ready: true
property QtObject options: QtObject {
property QtObject background: QtObject {
property QtObject widgets: QtObject {
%s
property string colorScheme: "default"
property bool enableShadows: false
property bool enableInnerShadow: false
property QtObject quote: QtObject { property string quoteText: "Opaque foreground"; property int fontSize: 16 }
}}}}
''' % defaults)
        put('qs/services/Translation.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
        put('qs/services/DateTime.qml', '''pragma Singleton
import QtQuick
QtObject { property QtObject clock: QtObject {
property date date: new Date(2026, 8, 9, 12, 30, 0)
property int hours: 12
property int minutes: 30
property int seconds: 0
}}
''')
        put('qs/modules/ii/background/widgets/AbstractBackgroundWidget.qml', 'import QtQuick\nItem { property string configEntryName: "" }')
        for name, body in {
            'StyledText': 'Text {}',
            'MaterialSymbol': 'Text { property real iconSize: 16; property int fill: 1; font.pixelSize: iconSize }',
            'StyledRectangularShadow': 'Item { property var target }',
        }.items():
            put(f'qs/modules/common/widgets/{name}.qml', 'import QtQuick\n' + body)
        put('qs/qmldir', 'module qs\n')
        for folder in sorted((out / 'qs').rglob('*')):
            if not folder.is_dir():
                continue
            entries = []
            for qml in sorted(folder.glob('*.qml')):
                singleton = 'singleton ' if 'pragma Singleton' in qml.read_text() else ''
                entries.append(f'{singleton}{qml.stem} 1.0 {qml.name}')
            if entries:
                put(str(folder.relative_to(out) / 'qmldir'), '\n'.join(entries) + '\n')
        put('tests/tst_WidgetTint.qml', (ROOT / 'tests/background/tst_WidgetTint.qml').read_text())
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        result = subprocess.run([runner, '-input', str(out / 'tests'), '-import', str(out)], env=env, text=True, capture_output=True, timeout=45)
        print(result.stdout, end='')
        print(result.stderr, end='')
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
