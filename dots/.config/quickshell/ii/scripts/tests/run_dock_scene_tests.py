#!/usr/bin/env python3
"""Run actual dock QML offscreen without Quickshell, IPC or persistent services.

Only native window anchoring/focus and system services are replaced. The popup
Loader, motion, folder delegates, keyed models and handlers are production code.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
QT = Path('/usr/lib64/qt6/bin')


def main():
    with tempfile.TemporaryDirectory(prefix='ii-dock-scene-') as directory:
        tmp = Path(directory)

        def module(name, files):
            path = tmp / name.replace('.', '/')
            path.mkdir(parents=True, exist_ok=True)
            entries = ['module ' + name]
            for name, body in files.items():
                (path / (name + '.qml')).write_text(body)
                entries.append(('singleton ' if 'pragma Singleton' in body else '') + name + ' 1.0 ' + name + '.qml')
            (path / 'qmldir').write_text('\n'.join(entries) + '\n')

        def singleton(body):
            return 'pragma Singleton\nimport QtQuick\nQtObject {\n' + body + '\n}'

        colors = {key: '#807090' for key in set(re.findall(r'(?:colors|m3colors)\.([A-Za-z0-9_]+)', '\n'.join(p.read_text() for p in (ROOT / 'modules/ii/dock').rglob('*.qml'))))}
        anim = 'property int duration: 120; property int type: Easing.InOutQuad; property var bezierCurve: [0,0,1,1,1,1]; property Component colorAnimation: ColorAnimation { duration: 120 }; property Component numberAnimation: NumberAnimation { duration: 120 }'
        module('qs.modules.common', {
            'Appearance': singleton('property var colors: ' + json.dumps(colors) + '\nproperty var m3colors: colors\nproperty var rounding: ({small:8,normal:17,full:9999})\nproperty var sizes: ({dockButtonSize:48,elevationMargin:8})\nproperty var font: ({pixelSize:{small:15,smaller:13,large:22}})\nproperty QtObject animation: QtObject {' + '\n'.join('property QtObject '+n+': QtObject {'+anim+'}' for n in ['elementMoveEnter','elementMoveFast','elementResize','dockMagnification']) + '}'),
            'Config': singleton('property var options: ({dock:{enablePreview:false},appearance:{transparency:{popups:true}}})')})
        module('qs', {'GlobalStates': singleton('property bool editMode: false; property real editProgress: 0')})
        module('qs.services', {
            'TaskbarApps': singleton('function getCachedDesktopEntry(id) { return null; }'),
            'HyprlandData': singleton('function toplevelOnScreen(window) { return true; }'),
            'Notifications': singleton('signal notify(var notification)'),
            'Translation': singleton('function tr(text) { return text; }')})
        module('qs.modules.common.functions', {'ColorUtils': singleton('function transparentize(color, alpha) { return color; }')})
        module('qs.modules.ii.editMode', {'EditRemoveBadge': 'import QtQuick\nItem { signal clicked() }', 'EditAddBadge': 'import QtQuick\nItem { signal clicked() }'})
        module('qs.modules.common.dock', {'DockIcon': 'import QtQuick\nItem { property string appId; property var desktopEntry; property bool isRunning }'})
        module('qs.modules.common.widgets', {
            'DashedBorder': 'import QtQuick\nRectangle { property real borderWidth; property real dashLength; property real gapLength }',
            'StyledText': 'import QtQuick\nText {}',
            'MaterialSymbol': 'import QtQuick\nText { property real iconSize: 20; font.pixelSize: iconSize }',
            'MaterialShape': 'import QtQuick\nRectangle { property string shapeString; property real implicitSize: 18; implicitWidth: implicitSize; implicitHeight: implicitSize }',
            'StyledRectangularShadow': 'import QtQuick\nItem { property Item target }',
            'RippleButton': '''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 0
 property bool rippleEnabled: false
 property color colBackgroundToggled: "transparent"
 property color colBackgroundToggledHover: "transparent"
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colRipple: "transparent"
 property var pressedAction
 property var releaseAction
 property var enteredAction
 property var exitedAction
 property var altAction
 property var positionChangedAction
 property var canceledAction
}'''})
        module('Quickshell.Widgets', {'IconImage': 'import QtQuick\nImage { property real implicitSize: 18 }'})
        module('Quickshell', {'Quickshell': singleton('function iconPath(name,fallback) { return ""; }')})
        dock = tmp / 'dock'
        shutil.copytree(ROOT / 'modules/ii/dock', dock)
        base = dock / 'widgets/DockContextMenuBase.qml'
        source = base.read_text().replace('import Quickshell.Hyprland', '')
        source = source.replace('sourceComponent: PopupWindow {', 'sourceComponent: Item {\n        property color color')
        start = source.index('        function requestAnchorUpdate()')
        end = source.index('        implicitWidth:', start)
        source = source[:start] + '        function requestAnchorUpdate() {}\n' + source[end:]
        source = re.sub(r'        HyprlandFocusGrab \{.*?\n        \}', '', source, flags=re.S)
        base.write_text(source)
        (dock / 'widgets/DockPreviewPopup.qml').write_text('import QtQuick\nItem { property var dockRoot; property var dockWindow; property var anchorItem; property bool compactMode; property var appTopLevel }')
        (dock / 'widgets/DockTooltip.qml').write_text('import QtQuick\nItem { property var parentItem; property string text; property bool showTooltip; property real tooltipOffset }')
        for name in ['DockAppIcon.qml', 'DockAppIndicator.qml']:
            (dock / name).write_text('import QtQuick\nItem {}')
        for test in (ROOT / 'tests/dockScene').glob('tst_*.qml'):
            shutil.copy(test, tmp / test.name)
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        binary = str(QT / 'qmltestrunner') if (QT / 'qmltestrunner').exists() else shutil.which('qmltestrunner')
        for path in [ROOT / 'tests/dock', tmp]:
            result = subprocess.run([binary, '-input', str(path), '-import', str(tmp)], env=env)
            if result.returncode:
                return result.returncode
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
