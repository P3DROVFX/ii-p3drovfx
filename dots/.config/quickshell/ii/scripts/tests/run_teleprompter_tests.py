#!/usr/bin/env python3
"""Run the real Teleprompter service offscreen.

The engine — scroll arithmetic, countdown, loop, clamps — lives in
services/Teleprompter.qml and is tested through its two splittable movers,
`advance(dtMs)` and `stepCountdown()`, so no test waits on real time.
qmltestrunner cannot load the Quickshell plugin, so Config and Appearance are
doubled and the Quickshell module is stubbed just enough for the service's
IpcHandler and clipboard read to exist; the service file itself is the real
one, copied verbatim into the stub module tree.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
QT = Path('/usr/lib64/qt6/bin')

CONFIG_STUB = '''pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property QtObject options: QtObject {
        property QtObject dynamicIsland: QtObject {
            property QtObject widgets: QtObject {
                property QtObject teleprompter: QtObject {
                    property bool enable: true
                    property int lines: 2
                    property int expandedLines: 5
                    property int width: 520
                    property int fontSize: 22
                    property bool bold: true
                    property int speed: 45
                    property bool loop: false
                    property int countdownSeconds: 3
                    property bool mirror: false
                    property bool showProgress: true
                    property bool holdVisible: true
                    property string text: ""
                    property int finishHoldSeconds: 4
                }
            }
        }
    }
}'''

APPEARANCE_STUB = '''pragma Singleton
import QtQuick
QtObject {
    property QtObject font: QtObject {
        property QtObject family: QtObject {
            property string main: "Stub Sans"
            property string reading: "Stub Reading"
        }
    }
    property bool reducedMotion: false
}'''

QUICKSHELL_STUB = '''pragma Singleton
import QtQuick
QtObject {
    property string clipboardText: "clipboard contents"
}'''

SINGLETON_STUB = '''import QtQuick
QtObject {
    default property list<QtObject> children2: []
}'''

IPCHANDLER_STUB = '''import QtQuick
QtObject {
    property string target: ""
}'''


def main():
    with tempfile.TemporaryDirectory(prefix='ii-teleprompter-') as directory:
        tmp = Path(directory)

        def module(name, files):
            path = tmp / name.replace('.', '/')
            path.mkdir(parents=True, exist_ok=True)
            entries = ['module ' + name]
            for filename, body in files.items():
                (path / (filename + '.qml')).write_text(body)
                entries.append(('singleton ' if 'pragma Singleton' in body else '')
                               + filename + ' 1.0 ' + filename + '.qml')
            (path / 'qmldir').write_text('\n'.join(entries) + '\n')

        module('Quickshell', {
            'Quickshell': QUICKSHELL_STUB,
            'Singleton': SINGLETON_STUB,
            'IpcHandler': IPCHANDLER_STUB,
        })
        module('qs.modules.common', {
            'Config': CONFIG_STUB,
            'Appearance': APPEARANCE_STUB,
        })
        # The service also imports these; a module with no types is skipped by
        # the resolver and the real (plugin-backed) one wins, so each stub
        # carries a dummy type.
        module('Quickshell.Io', {'StubIo': 'import QtQuick\nQtObject {}'})
        module('qs.modules.common.functions', {'StubFn': 'import QtQuick\nQtObject {}'})
        module('qs.services', {
            'Teleprompter': (ROOT / 'services/Teleprompter.qml').read_text(),
        })

        tests = tmp / 'tst_Teleprompter.qml'
        tests.write_text((ROOT / 'tests/teleprompter/tst_Teleprompter.qml').read_text())

        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        binary = str(QT / 'qmltestrunner') if (QT / 'qmltestrunner').exists() else shutil.which('qmltestrunner')
        return subprocess.run([binary, '-input', str(tests), '-import', str(tmp)], env=env).returncode


if __name__ == '__main__':
    raise SystemExit(main())
