#!/usr/bin/env python3
"""Run the real ScreenshotOverlayContent offscreen with its phone share button.

The overlay file is copied as-is; only the shell services it reads are doubled
(GlobalStates, Config, Directories, Appearance, KDE Connect, Translation), along
with the Process and execDetached that would start real commands. The doubles
record what the overlay asks for, so the tests see the copy command and the
share call without running magick, notify-send or kdeconnectd.

Covered contracts (tests/screenshotOverlay/tst_ScreenshotPhoneShare.qml):
  - the "Send to <phone>" button shows only with KDE Connect on, a paired
    reachable phone and the share plugin
  - it is the last toolbar button, with the phone icon
  - a click copies the region (or the whole capture) and shares that copy
  - the overlay closes only after the copy has finished
  - a failed copy shares nothing
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
QT = Path('/usr/lib64/qt6/bin')


def main():
    with tempfile.TemporaryDirectory(prefix='ii-screenshot-phone-') as directory:
        tmp = Path(directory)

        def module(name, files):
            path = tmp / name.replace('.', '/')
            path.mkdir(parents=True, exist_ok=True)
            entries = ['module ' + name]
            for filename, body in files.items():
                (path / (filename + '.qml')).write_text(body)
                entries.append(('singleton ' if 'pragma Singleton' in body else '') + filename + ' 1.0 ' + filename + '.qml')
            (path / 'qmldir').write_text('\n'.join(entries) + '\n')

        def singleton(body, imports=('QtQuick',)):
            lines = ['pragma Singleton'] + ['import ' + name for name in imports]
            return '\n'.join(lines) + '\nQtObject {\n' + body + '\n}'

        module('Harness', {'Harness': singleton('''property var execs: []
property var started: []
property var shares: []
function reset() {
    execs = []
    started = []
    shares = []
}''')})

        module('Quickshell', {
            'Quickshell': singleton('function execDetached(command) { Harness.execs.push(command) }', ('QtQuick', 'Harness'))})
        module('Quickshell.Io', {'Process': '''import QtQuick
import Harness

QtObject {
    id: proc
    property var command: []
    property bool running: false
    signal exited(int exitCode, int exitStatus)
    onRunningChanged: {
        if (running)
            Harness.started.push(proc)
    }
    function finish(code) {
        running = false
        exited(code, 0)
    }
}'''})
        module('Quickshell.Widgets', {'ClippingRectangle': 'import QtQuick\nRectangle {}'})

        module('qs', {'GlobalStates': singleton('''property bool screenshotOverlayOpen: true
property string screenshotOverlayImagePath: ""
property string screenshotOverlayMonitor: ""
property real screenshotOverlayRegionX: 0
property real screenshotOverlayRegionY: 0
property real screenshotOverlayRegionW: 0
property real screenshotOverlayRegionH: 0''')})

        timing = '({duration: 1, type: Easing.OutCubic, bezierCurve: [0.2, 0, 0, 1, 1, 1]})'
        module('qs.modules.common', {
            'Appearance': singleton(f'''property var colors: ({{colLayer0: "#1e1e1e", colPrimary: "#b0a0ff", colPrimaryContainer: "#3d3560", colPrimaryContainerHover: "#4a4170", colPrimaryContainerActive: "#2f2950", colOnPrimaryContainer: "#eeeaff", colErrorContainer: "#5c1d1d", colErrorContainerHover: "#6e2a2a", colErrorContainerActive: "#4a1515", colOnErrorContainer: "#ffdad6"}})
property var rounding: ({{scale: 1, small: 8, normal: 17, large: 24, full: 9999}})
property var font: ({{pixelSize: ({{normal: 14}})}})
property real animMultiplier: 1
readonly property var timing: {timing}
property var animation: ({{
    elementMove: timing,
    elementMoveEnter: timing,
    elementMoveExit: timing,
    elementMoveFast: ({{numberAnimation: numberAnim, colorAnimation: colorAnim}})
}})
property Component numberAnim: Component {{
    NumberAnimation {{ duration: 1 }}
}}
property Component colorAnim: Component {{
    ColorAnimation {{ duration: 1 }}
}}''', ('QtQuick',)),
            'Config': singleton('property var options: ({screenSnip: ({savePath: ""})})'),
            'Directories': singleton(f'''property string home: "/home/test"
property string phoneShare: "/home/test/.cache/quickshell/phone-share"
property string assetsPath: "{ROOT}/assets"''')})
        module('qs.modules.common.functions', {
            'ColorUtils': singleton('function transparentize(color, amount) { return color }')})
        module('qs.modules.common.widgets', {
            'MaterialSymbol': 'import QtQuick\nText {\n    property real iconSize: 16\n    property real fill: 0\n}',
            'StyledText': 'import QtQuick\nText {}'})
        module('qs.services', {
            'KdeConnectService': singleton('''property bool serviceEnabled: true
property bool activeReachable: true
property var activeDevice: ({})
property string activeDeviceId: ""
property string activeDeviceDisplayName: ""
function shareUrl(devId, url) { Harness.shares.push({devId: devId, url: url}) }''', ('QtQuick', 'Harness')),
            'Translation': singleton('function tr(text) { return text }'),
            'Cliphist': singleton('property var entries: []\nfunction deleteEntry(entry) {}')})

        # The real overlay, untouched, next to the test that imports it.
        overlay = tmp / 'overlay'
        overlay.mkdir()
        shutil.copy(ROOT / 'modules/ii/screenshotOverlay/ScreenshotOverlayContent.qml', overlay / 'ScreenshotOverlayContent.qml')

        tests = tmp / 'tst_ScreenshotPhoneShare.qml'
        tests.write_text((ROOT / 'tests/screenshotOverlay/tst_ScreenshotPhoneShare.qml').read_text())

        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        binary = str(QT / 'qmltestrunner') if (QT / 'qmltestrunner').exists() else shutil.which('qmltestrunner')
        return subprocess.run([binary, '-input', str(tests), '-import', str(tmp)], env=env).returncode


if __name__ == '__main__':
    raise SystemExit(main())
