"""Exercise the timetable picker hosts offscreen with stubbed qs modules.

Runs Qt Quick Test, never Quickshell. The real `DeferredTimePicker` and
`DeferredDatePicker` are loaded together with the real popups they host, so the
contract that matters is checked against the shipped code: nothing is built
while the page is idle, the first `open()` builds the popup and opens it, the
popup's `accepted` reaches the host and the second request reuses the instance.
"""
from pathlib import Path
import os, shutil, subprocess, tempfile

root = Path(__file__).resolve().parents[2]
timetable = root / "modules/ii/cheatsheet/timetable"
temporary = tempfile.TemporaryDirectory(prefix="ii-picker-hosts-")
out = Path(temporary.name)


def put(rel, text):
    p = out / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


for name in ("DeferredTimePicker.qml", "DeferredDatePicker.qml",
             "TimePickerPopup.qml", "DatePickerPopup.qml", "TimetableHelpers.js"):
    put(f"hosts/{name}", (timetable / name).read_text())

put('qs/modules/common/widgets/StyledText.qml',
    'import QtQuick\nText { property bool animateChange: false; property real animationDistanceX: 0; '
    'property real animationDistanceY: 0; property bool tintText: false; font.pixelSize: 14; color: "white" }')
put('qs/modules/common/widgets/MaterialSymbol.qml',
    'import QtQuick\nText { property real iconSize: 16; property real fill: 0; font.pixelSize: iconSize }')
put('qs/modules/common/widgets/RippleButton.qml', '''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 10
 property bool toggled: false
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colBackgroundActive: "transparent"
 property color colRipple: "transparent"
}
''')
put('qs/modules/common/widgets/RippleButtonWithIcon.qml', '''import QtQuick
import QtQuick.Controls
Button {
 property real buttonRadius: 10
 property bool centerContent: true
 property string materialIcon: ""
 property bool materialIconFill: false
 property string mainText: ""
 property real iconPixelSize: 16
 property real textPixelSize: 12
 property int mainTextWeight: Font.Normal
 property color colText: "white"
 property color colBackground: "transparent"
 property color colBackgroundHover: "transparent"
 property color colBackgroundActive: "transparent"
}
''')
put('qs/modules/common/widgets/StyledTextInput.qml', '''import QtQuick
import QtQuick.Controls
TextField {
 property bool tintText: false
 property color colText: "white"
 property color colBackground: "transparent"
}
''')
put('qs/modules/common/widgets/DashedBorder.qml', '''import QtQuick
Item {
 property color color: "transparent"
 property int borderWidth: 1
 property real radius: 0
 property int dashLength: 4
 property int gapLength: 3
}
''')
put('qs/modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({ colPrimary: "#ffb787", colOnSurface: "#e6e1e5", colOnSurfaceVariant: "#cac4d0", colPrimaryContainer: "#6e3900", colOnPrimaryContainer: "#ffdcc5", colPrimaryHover: "#ffc299", colPrimaryActive: "#ffa066", colLayer1: "#1c1b1f", colLayer1Hover: "#2a2a2a", colLayer2: "#211f26", colOnLayer1: "#e6e1e5", colOnLayer1Inactive: "#777777", colSurface: "#141218", colSurfaceContainerHighest: "#2b2927", colSecondaryContainer: "#4a4458", colOnSecondaryContainer: "#e8def8", colTertiaryContainer: "#633b48", colOnTertiaryContainer: "#ffd8e4", colError: "#ffb4ab", colErrorContainer: "#93000a", colOnErrorContainer: "#ffdad6", colOutline: "#938f99", colScrim: "#88000000", colSurfaceContainerHighestHover: "#3d3935" })
 property var rounding: ({ small: 8, normal: 12, large: 16, verysmall: 4, full: 999 })
 property var font: ({ pixelSize: ({ smallest: 10, smaller: 11, small: 12, smallie: 13, normal: 14, large: 16, larger: 20, huge: 28 }), family: ({ numbers: "monospace", main: "sans-serif" }) })
 property var m3colors: ({ m3surfaceContainerHigh: "#2b2927", m3surfaceContainerHighest: "#33302c", m3surfaceContainer: "#211f26" })
 property Component num: NumberAnimation { duration: 1 }
 property Component col: ColorAnimation { duration: 1 }
 property var elementMove: ({ duration: 1, numberAnimation: num, colorAnimation: col })
 property var animation: ({ elementMoveFast: elementMove, elementMoveEnter: elementMove, elementMoveExit: elementMove })
 property var animationCurves: ({ emphasizedDecel: [0.05, 0.7, 0.1, 1], emphasizedAccel: [0.3, 0, 0.8, 0.15] })
}
''')
put('qs/modules/common/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var options: ({
  time: { format: "hh:mm", firstDayOfWeek: 1 },
  calendar: { locale: "en_US", timetable: { moonPhases: { enable: false } } }
 })
}
''')
put('qs/modules/common/functions/ColorUtils.qml',
    'pragma Singleton\nimport QtQuick\nQtObject { function applyAlpha(c, a) { return c; } }')
put('qs/modules/common/functions/DateUtils.qml',
    'pragma Singleton\nimport QtQuick\nQtObject { function is12HourTimeFormat(f) { return false; } }')
put('qs/services/Translation.qml',
    'pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
put('qs/services/DateTime.qml',
    'pragma Singleton\nimport QtQuick\nQtObject { property var clock: ({ date: new Date(2026, 8, 23) }) }')
put('qs/services/CalendarService.qml',
    'pragma Singleton\nimport QtQuick\nQtObject { property var eventsByDay: ({}) }')

for folder in out.rglob('*'):
    if not folder.is_dir():
        continue
    qmls = sorted(folder.glob('*.qml'))
    if not qmls:
        continue
    (folder / 'qmldir').write_text(
        'module ' + '.'.join(folder.relative_to(out).parts) + '\n'
        + '\n'.join(('singleton ' if 'pragma Singleton' in p.read_text() else '') + p.stem + ' 1.0 ' + p.name
                    for p in qmls) + '\n')

put('tests/tst_picker_hosts.qml', '''import QtQuick
import QtTest
import "../hosts"

Item {
 width: 800
 height: 700

 DeferredTimePicker { id: timeHost; anchors.fill: parent }
 DeferredDatePicker { id: dateHost; anchors.fill: parent }

 property int acceptedHour: -1
 property int acceptedMinute: -1

 TestCase {
  name: "PickerHosts"
  when: windowShown

  function test_time_picker_builds_on_first_request() {
   compare(timeHost.item, null, "host must not build the popup with the page");

   timeHost.target = "end";
   timeHost.open(9, 30, "Ends at");

   verify(timeHost.item !== null, "popup built on first request");
   verify(timeHost.item.opened === true, "popup opened");
   compare(timeHost.item.hour, 9);
   compare(timeHost.item.minute, 30);
   compare(timeHost.target, "end");

   const built = timeHost.item;
   timeHost.close();
   verify(timeHost.item.opened === false, "close propagates");

   timeHost.open(14, 5, "Ends at");
   verify(timeHost.item === built, "second request reuses the built popup");
   compare(timeHost.item.hour, 14);
   verify(timeHost.item.opened === true, "reopened");
  }

  function test_time_picker_forwards_accepted() {
   timeHost.accepted.connect(function(hour, minute) {
    acceptedHour = hour;
    acceptedMinute = minute;
   });
   timeHost.open(7, 15, "Starts at");
   timeHost.item.confirm();
   compare(acceptedHour, 7);
   compare(acceptedMinute, 15);
   verify(timeHost.item.opened === false, "confirm closes the picker");
  }

  function test_date_picker_builds_on_first_request() {
   compare(dateHost.item, null, "host must not build the popup with the page");

   dateHost.purpose = "navigate";
   dateHost.open(new Date(2026, 8, 10), "Go to day");

   verify(dateHost.item !== null, "popup built on first request");
   verify(dateHost.item.opened === true, "popup opened");
   compare(dateHost.item.selected.getDate(), 10);
   compare(dateHost.purpose, "navigate");
   verify(dateHost.item.cells.length >= 28, "month grid exists inside the built popup");

   const built = dateHost.item;
   dateHost.close();
   dateHost.open(new Date(2026, 8, 12), "Go to day");
   verify(dateHost.item === built, "second request reuses the built popup");
   compare(dateHost.item.selected.getDate(), 12);
  }
 }
}
''')

runner = shutil.which("qmltestrunner6") or "/usr/lib64/qt6/bin/qmltestrunner"
try:
    result = subprocess.run([runner, "-input", str(out / "tests"), "-import", str(out)],
                            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software"},
                            timeout=60)
    raise SystemExit(result.returncode)
finally:
    temporary.cleanup()