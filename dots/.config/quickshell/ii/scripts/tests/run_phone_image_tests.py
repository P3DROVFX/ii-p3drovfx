#!/usr/bin/env python3
"""Run the real BluetoothDeviceImages service offscreen.

The picture of a phone is decided in one place — services/BluetoothDeviceImages.qml
— and consumed by the dock phone widget, the phone popups and the island
glances. qmltestrunner cannot load the Quickshell plugin, so FileView, Config,
BluetoothStatus and Directories are doubled; the service, the phone icon index
(assets/icons/phone/index.json) and the catalog art paths are the real ones.

Covered contracts:
  - the index loads with normalised keys (marketing names in, model names out)
  - the Bluetooth name of the phone picks its own photo
  - another device's photo is never used for the phone
  - the single paired phone's photo is used, two of them are never guessed
  - the dock chain: photo, then model drawing, then generic drawing
  - the popup chain keeps catalog art below the photo
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
    with tempfile.TemporaryDirectory(prefix='ii-phone-image-') as directory:
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
        module('qs.modules.common', {
            'Config': singleton('property var options: ({})'),
            'Directories': singleton(f'property string shellConfig: "{ROOT}/.tmp-shell-config"\nproperty string assetsPath: "{ROOT}/assets"')})
        module('qs.services', {
            'BluetoothStatus': singleton('property var friendlyDeviceList: []'),
            'BluetoothDeviceImages': (ROOT / 'services/BluetoothDeviceImages.qml').read_text()})

        tests = tmp / 'tst_BluetoothDeviceImages.qml'
        tests.write_text((ROOT / 'tests/phoneImage/tst_BluetoothDeviceImages.qml').read_text())

        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        binary = str(QT / 'qmltestrunner') if (QT / 'qmltestrunner').exists() else shutil.which('qmltestrunner')
        return subprocess.run([binary, '-input', str(tests), '-import', str(tmp)], env=env).returncode


if __name__ == '__main__':
    raise SystemExit(main())