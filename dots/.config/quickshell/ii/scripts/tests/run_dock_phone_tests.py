#!/usr/bin/env python3
"""Run the real DockPhoneWidget offscreen.

The dock phone shortcut no longer decides its own picture: it asks
BluetoothDeviceImages, which puts the photo the user attached to the phone's
Bluetooth device over the generated drawing of the model. This harness keeps the
widget and that service real, and doubles only the pieces that need a Wayland
session or a running shell (popups, processes, KDE Connect/scrcpy state).

Covered contracts:
  - a photo attached to the phone's Bluetooth device replaces the drawing
  - without one, the drawing of the model KDE Connect reports is used
  - an unknown model falls back to the generic drawing
  - a drawing takes the full app-tile button, a photo the tighter box
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
QT = Path('/usr/lib64/qt6/bin')


def main():
    with tempfile.TemporaryDirectory(prefix='ii-dock-phone-') as directory:
        tmp = Path(directory)

        def module(name, files):
            path = tmp / name.replace('.', '/')
            path.mkdir(parents=True, exist_ok=True)
            entries = ['module ' + name]
            for filename, body in files.items():
                (path / (filename + '.qml')).write_text(body)
                entries.append(('singleton ' if 'pragma Singleton' in body else '') + filename + ' 1.0 ' + filename + '.qml')
            (path / 'qmldir').write_text('\n'.join(entries) + '\n')

        def singleton(body):
            return 'pragma Singleton\nimport QtQuick\nQtObject {\n' + body + '\n}'

        # The photo the user attached to the phone's MAC, as a real file: the
        # widget must end up with a loaded image, not just a URL.
        shell_config = tmp / 'shell-config'
        (shell_config / 'bluetooth_images').mkdir(parents=True)
        shutil.copy(ROOT / 'assets/icons/phone/phone-generic-android.png',
                    shell_config / 'bluetooth_images/device_64_1B_2F_9B_95_CE.png')

        index = (ROOT / 'assets/icons/phone/index.json').read_text()
        module('Quickshell', {
            'Quickshell': singleton('function iconPath(name, fallback) { return ""; }'),
            'Singleton': 'import QtQuick\nItem {}'})
        module('Quickshell.Io', {'FileView': '''import QtQuick

Item {
    id: view
    property string path
    property bool watchChanges: false
    property bool printErrors: true
    property string fileText: ''' + json.dumps(index) + '''
    signal loaded()
    function text() { return view.fileText }
    Component.onCompleted: if (view.path !== "") view.loaded()
}'''})
        module('qs', {'GlobalStates': singleton('property bool editMode: false')})
        module('qs.modules.common', {
            'Appearance': singleton('property var colors: ({colPrimary: "#807090"})\nproperty var rounding: ({full: 9999, normal: 17, small: 8})\nproperty var sizes: ({dockButtonSize: 48, elevationMargin: 8})'),
            'Config': singleton('property var options: ({})'),
            'Directories': singleton(f'property string shellConfig: "{shell_config}"\nproperty string assetsPath: "{ROOT}/assets"')})
        module('qs.modules.common.widgets', {'StyledText': 'import QtQuick\nText {}'})
        module('qs.services', {
            'BluetoothStatus': singleton('property var friendlyDeviceList: []'),
            'BluetoothDeviceImages': (ROOT / 'services/BluetoothDeviceImages.qml').read_text(),
            'Translation': singleton('function tr(text) { return text; }'),
            'KdeConnectService': singleton('''property string activeDeviceId: ""
property bool activeReachable: false
property var activeDevice: null
property string activeDeviceDisplayName: ""
property bool scrcpyRunning: false
property bool scrcpyLaunching: false
property bool scrcpyAvailable: true
property bool adbReachable: true
function focusScrcpyWindow() {}'''),
            'PhoneScrcpyService': singleton('''property bool mirrorRunning: false
property bool mirrorLaunching: false
property bool available: true
function launchMirror() {}
function focusMirror() {}'''),
            'PhoneMirrorService': singleton('function _probeDeviceSize() {}')})

        dock = tmp / 'dock'
        shutil.copytree(ROOT / 'modules/ii/dock', dock)
        # The menu and the tooltip need a Wayland session and a live dock; the
        # widget only calls into the menu, so both stand in as plain items.
        (dock / 'DockPhoneContextMenu.qml').write_text('''import QtQuick

Item {
    property var anchorItem
    property var geometryItem
    property bool active: false
    function open() {}
}''')
        (dock / 'widgets/DockTooltip.qml').write_text('''import QtQuick

Item {
    property var parentItem
    property string text
    property bool showTooltip
    property real tooltipOffset
}''')

        tests = tmp / 'tst_DockPhoneWidget.qml'
        tests.write_text((ROOT / 'tests/dockPhone/tst_DockPhoneWidget.qml').read_text())

        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        binary = str(QT / 'qmltestrunner') if (QT / 'qmltestrunner').exists() else shutil.which('qmltestrunner')
        return subprocess.run([binary, '-input', str(tests), '-import', str(tmp)], env=env).returncode


if __name__ == '__main__':
    raise SystemExit(main())