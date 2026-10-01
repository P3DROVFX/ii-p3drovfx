#!/usr/bin/env python3
"""Run a real dock window widget offscreen.

run_dock_scene_tests.py stubs both DockPreviewPopup.qml and DockTooltip.qml, so
their own behaviour is not covered there. This harness keeps the production
files and replaces only native window anchoring/focus and the Quickshell
Wayland types they touch (PopupWindow, ScreencopyView, PopupAdjustment, Edges).

    run_dock_preview_popup_tests.py [--test tests/dockScene/<file>.qml]

Covered contracts:
  - the window preview: transient hover does NOT commit a capture target
    (settle timer), a settled target commits and stays while crossing icons,
    preview slot geometry is fixed before the first frame, and the blur layer
    disables itself at radius 0
  - DockTooltip: anchoring is only computed while the tooltip is shown, and
    keeps following the icon it points at
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
QT = Path('/usr/lib64/qt6/bin')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', default='tests/dockScene/tst_DockPreviewPopup.qml',
                        help='test file, relative to the repository root')
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix='ii-dock-preview-') as directory:
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

        module('qs.modules.common', {
            'Appearance': singleton('''
                property var colors: ({colLayer0: "#807090", colLayer1Hover: "#807090", colLayer1Active: "#807090", colSurfaceContainer: "#807090", colOnSurface: "#807090", colOnLayer1: "#807090", colOutlineVariant: "#807090", colLayer0Border: "#807090", m3surfaceContainer: "#807090"})
                property var m3colors: ({m3onSurface: "#807090", m3surfaceContainer: "#807090"})
                property var rounding: ({small:8, normal:17, full:9999})
                property var sizes: ({dockButtonSize:48, elevationMargin:8})
                property var font: ({pixelSize: ({small:15, smallest:12, normal:16})})
                property real animMultiplier: 1.0
                property QtObject animation: QtObject {
                    property QtObject elementResize: QtObject {
                        property int duration: 40
                        property int type: Easing.InOutQuad
                        property var bezierCurve: [0,0,1,1,1,1]
                        property Component numberAnimation: Component { NumberAnimation { duration: 40 } }
                    }
                    property QtObject elementMoveFast: QtObject {
                        property int duration: 40
                        property int type: Easing.InOutQuad
                        property var bezierCurve: [0,0,1,1,1,1]
                        property Component numberAnimation: Component { NumberAnimation { duration: 40 } }
                    }
                }
            '''),
            'Config': singleton('property var options: ({dock: {maxWindowPreviewWidth: 300, maxWindowPreviewHeight: 200, widgetRadius: -1, enablePreview: true}, appearance: ({transparency: ({popups: true})})})'),
        })
        module('qs.services', {
            # The popup filters committed toplevels through ToplevelManager;
            # the test drives membership by mutating `values`.
            'ToplevelManager': singleton('property var toplevels: QtObject { property var values: [] }'),
            'Translation': singleton('function tr(text) { return text; }'),
        })
        module('qs', {'GlobalStates': singleton('property bool editMode: false')})
        module('qs.modules.common.widgets', {
            'StyledText': 'import QtQuick\nText {}',
            'MaterialSymbol': 'import QtQuick\nText { property real iconSize: 20; font.pixelSize: iconSize }',
            'StyledRectangularShadow': 'import QtQuick\nItem { property Item target }',
            'RippleButton': '''import QtQuick
import QtQuick.Controls
Button {
    property real buttonRadius: 0
    property color colBackground: "transparent"
    property color colBackgroundHover: "transparent"
    property color colBackgroundActive: "transparent"
    property color colRipple: "transparent"
    property var middleClickAction: null
}''',
            'ButtonGroup': '''import QtQuick
import QtQuick.Layouts
Rectangle {
    default property alias groupData: rowLayout.data
    property real contentWidth: 0
    width: contentWidth
    implicitHeight: rowLayout.implicitHeight
    RowLayout { id: rowLayout; anchors.fill: parent }
}''',
        })
        module('qs.modules.common.functions', {'ColorUtils': singleton('function transparentize(color, alpha) { return color; }')})
        module('Quickshell', {
            'PopupAnchorStub': '''import QtQuick
QtObject {
    property var window: null
    property var adjustment: 0
    property var edges: 0
    property var gravity: 0
    property PopupRectStub rect: PopupRectStub {}
    signal anchoring()
}''',
            'PopupRectStub': '''import QtQuick
QtObject {
    property real x: 0
    property real y: 0
}''',
            'PopupWindow': '''import QtQuick
Item {
    default property alias data: inner.data
    property color color: "transparent"
    property var dockWindow: null
    property PopupAnchorStub anchor: PopupAnchorStub {}
    Item { id: inner }
}''',
            'ScriptModel': '''import QtQuick
ListModel {
    property var values: []
    function sync() { clear(); for (const v of values) append({modelData: v}); }
    onValuesChanged: sync()
    Component.onCompleted: if (count === 0) sync()
}'''})
        module('Quickshell.Wayland', {
            'ScreencopyView': '''import QtQuick
Item {
    // Minimal stand-in: geometry behaves like the real view, content does
    // not arrive until the test's fake frame timer sets sourceSize.
    property var captureSource: null
    property bool live: false
    property bool paintCursor: false
    property size constraintSize: "0x0"
    property size sourceSize: "0x0"
    readonly property bool hasContent: sourceSize.width > 0 && sourceSize.height > 0
    implicitWidth: {
        const source = hasContent ? sourceSize : Qt.size(1600, 900);
        if (constraintSize.width > 0 && constraintSize.height > 0) {
            const scale = Math.min(constraintSize.width / source.width, constraintSize.height / source.height);
            return source.width * scale;
        }
        return source.width;
    }
    implicitHeight: {
        const source = hasContent ? sourceSize : Qt.size(1600, 900);
        if (constraintSize.width > 0 && constraintSize.height > 0) {
            const scale = Math.min(constraintSize.width / source.width, constraintSize.height / source.height);
            return source.height * scale;
        }
        return source.height;
    }
    function captureFrame() {}
}''',
            'Edges': 'pragma Singleton\nimport QtQml\nQtObject { enum Edges { Top = 1, Bottom = 2, Left = 4, Right = 8 } }',
            'PopupAdjustment': 'pragma Singleton\nimport QtQml\nQtObject { enum PopupAdjustment { None = 0 } }',
        })
        module('Quickshell.Widgets', {
            'IconImage': 'import QtQuick\nImage { property real implicitSize: 18 }',
            'WrapperRectangle': '''import QtQuick
Item {
    default property alias content: inner.data
    property real margin: 0
    property color color: "transparent"
    property real radius: 0
    implicitWidth: inner.implicitWidth + margin * 2
    implicitHeight: inner.implicitHeight + margin * 2
    Item { id: inner; anchors.fill: parent; anchors.margins: parent.margin }
}''',
        })

        dock = tmp / 'dock'
        shutil.copytree(ROOT / 'modules/ii/dock', dock)
        # DockContextMenuBase owns PopupWindow/HyprlandFocusGrab; the popup under
        # test only needs the file to import cleanly for DockGroupPopup.
        base = dock / 'widgets/DockContextMenuBase.qml'
        source = base.read_text().replace('import Quickshell.Hyprland', '')
        source = source.replace('sourceComponent: PopupWindow {', 'sourceComponent: Item {\n        property color color')
        start = source.index('        function requestAnchorUpdate()')
        end = source.index('        implicitWidth:', start)
        source = source[:start] + '        function requestAnchorUpdate() {}\n' + source[end:]
        import re
        source = re.sub(r'        HyprlandFocusGrab \{.*?\n        \}', '', source, flags=re.S)
        base.write_text(source)

        source = ROOT / args.test
        tests = tmp / source.name
        tests.write_text(source.read_text())

        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        binary = str(QT / 'qmltestrunner') if (QT / 'qmltestrunner').exists() else shutil.which('qmltestrunner')
        return subprocess.run([binary, '-input', str(tests), '-import', str(tmp)], env=env).returncode


if __name__ == '__main__':
    raise SystemExit(main())
