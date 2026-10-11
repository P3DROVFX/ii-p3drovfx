import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * The lock surface's islands, rebuilt for the greeter:
 *  - bottom centre: password field + confirm;
 *  - bottom left: battery, caps lock, keyboard layout, and before them the
 *    session and user pills, which open into their lists (MorphPicker);
 *  - bottom right: sleep, power, reboot.
 * Sizes, colours and motion follow modules/ii/lock/LockSurface.qml.
 */
FocusScope {
    id: root

    signal loginSucceeded

    property bool busy: false
    property bool failed: false
    property bool capsLock: keyboard ? keyboard.capsLock : false

    // ── users and sessions ─────────────────────────────────────────────────
    // The models are C++ list models; their rows are read through Instantiators.
    Instantiator {
        id: users
        model: userModel
        delegate: QtObject {
            required property string name
            required property string realName
            required property string icon
        }
    }
    Instantiator {
        id: sessions
        model: sessionModel
        // Read through `model`: a role a given SDDM build lacks reads as undefined.
        delegate: QtObject {
            required property var model
            readonly property string name: model.name ?? ""
            // Session::Type: 1 X11, 2 Wayland.
            readonly property string kind: model.type === 2 ? "Wayland" : model.type === 1 ? "X11" : ""
        }
    }
    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    readonly property var currentUser: users.count > root.userIndex ? users.objectAt(root.userIndex) : null
    readonly property string userName: currentUser ? currentUser.name : (userModel.lastUser || "")
    readonly property string displayName: currentUser ? (currentUser.realName || currentUser.name) : root.userName
    readonly property string sessionName: {
        const s = sessions.count > root.sessionIndex ? sessions.objectAt(root.sessionIndex) : null;
        return s ? s.name : "";
    }
    // SDDM hands every user without a picture its own generic face; the lock
    // shows its padlock instead, so that face counts as no picture at all.
    function avatarFor(user) {
        if (!user)
            return "";
        const icon = String(user.icon || "");
        // The greeter may hand it over as a file:// URL; compare the path.
        const path = icon.replace(/^file:\/\//, "");
        return icon === "" || path.indexOf("/usr/share/sddm/faces/") === 0 ? "" : (icon.startsWith("file:") || icon.startsWith("image:") ? icon : "file://" + icon);
    }

    function tryLogin() {
        if (root.busy || root.userName === "")
            return;
        root.busy = true;
        sddm.login(root.userName, passwordBox.text, root.sessionIndex);
    }
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    function closeDialogs() {
        layoutDialog.close();
        sessionPicker.close();
        userPicker.close();
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            root.failed = true;
            passwordBox.text = "";
            wrongPasswordShake.restart();
            root.forceFieldFocus();
        }
        function onLoginSucceeded() {
            root.loginSucceeded();
        }
    }

    // ── entrance ───────────────────────────────────────────────────────────
    property real toolbarScale: 0.9
    property real toolbarOpacity: 0
    Behavior on toolbarScale {
        NumberAnimation {
            duration: Theme.ms(500)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveFastSpatial
        }
    }
    Behavior on toolbarOpacity {
        NumberAnimation {
            duration: Theme.ms(200)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveEffects
        }
    }
    Component.onCompleted: {
        root.applyLeftOrder();
        root.forceFieldFocus();
        root.toolbarScale = 1;
        root.toolbarOpacity = 1;
    }

    // ── keys ───────────────────────────────────────────────────────────────
    Keys.onPressed: event => {
        if (event.key === Qt.Key_CapsLock)
            root.capsLock = !root.capsLock;
        if (event.key === Qt.Key_Escape) {
            passwordBox.text = "";
            root.closeDialogs();
        }
        root.forceFieldFocus();
    }

    MouseArea {
        anchors.fill: parent
        onPressed: {
            root.closeDialogs();
            root.forceFieldFocus();
        }
    }

    // ── centred clock (only when the lock shows one) ───────────────────────
    Loader {
        anchors.centerIn: parent
        active: Theme.clockStyle !== "none"
        opacity: root.toolbarOpacity
        sourceComponent: Theme.clockStyle === "cookie" ? cookieClock : digitalClock
        Component {
            id: digitalClock
            DigitalClock {}
        }
        Component {
            id: cookieClock
            CookieClock {}
        }
    }

    // ── bottom centre: password ────────────────────────────────────────────
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        TextField {
            id: passwordBox
            objectName: "passwordBox"
            Layout.fillHeight: true
            Layout.rightMargin: -Layout.leftMargin
            implicitWidth: 200
            padding: 10
            clip: true
            focus: true
            enabled: !root.busy
            echoMode: TextInput.Password
            passwordCharacter: "●"
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            placeholderText: root.failed ? qsTr("Incorrect password") : qsTr("Enter password")
            placeholderTextColor: Theme.colSubtext
            color: Theme.transparentize(Theme.colOnLayer1, Theme.materialShapeChars ? 1 : 0)
            selectedTextColor: Theme.materialShapeChars ? "transparent" : Theme.m3onSecondaryContainer
            selectionColor: Theme.materialShapeChars ? "transparent" : Theme.m3secondaryContainer
            renderType: Text.NativeRendering
            font {
                family: Theme.fontMain
                pixelSize: Theme.pxSmall
                hintingPreference: Font.PreferFullHinting
                variableAxes: Theme.axesMain
            }
            background: Rectangle {
                color: Theme.colLayer1
                radius: Theme.roundingFull
            }

            onTextChanged: if (text.length > 0) root.failed = false
            onAccepted: root.tryLogin()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_CapsLock)
                    root.capsLock = !root.capsLock;
                if (event.key === Qt.Key_Escape) {
                    passwordBox.text = "";
                    root.closeDialogs();
                    event.accepted = true;
                }
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            ErrorShake {
                id: wrongPasswordShake
                target: passwordBox
            }

            Loader {
                active: Theme.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: passwordBox.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        IslandButton {
            id: confirmButton
            implicitWidth: height
            toggled: true
            enabled: !root.busy
            colBackgroundToggled: Theme.m3primary
            onClicked: root.tryLogin()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: "arrow_right_alt"
                color: confirmButton.enabled ? Theme.m3onPrimary : Theme.colSubtext
            }
        }
    }

    // ── bottom left: status ────────────────────────────────────────────────
    Toolbar {
        id: leftIsland
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        // Layouts skip hidden children, so an island with nothing to show has no content width.
        visible: contentWidth > 0

        // Drawn in the order the lock uses (islands_left); see applyLeftOrder().
        BatteryButton {
            id: batteryButton
            readonly property bool wanted: root.leftWanted("battery")
            visible: wanted && available
        }

        IslandButton {
            id: capsLockPill
            readonly property bool wanted: root.leftWanted("capsLock")
            Layout.preferredWidth: root.capsLock && wanted ? 100 : 0
            visible: Layout.preferredWidth > 0
            clip: true
            pointingHandCursor: false
            colBackground: Theme.m3secondaryContainer
            colBackgroundHover: Theme.colSecondaryContainerHover
            colRipple: Theme.colSecondaryContainerActive
            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                verticalAlignment: Text.AlignVCenter
                text: "keyboard_capslock"
                iconSize: 22
                color: Theme.m3onSecondaryContainer
                fill: 1
            }
        }

        IslandButton {
            id: layoutButton
            readonly property bool showSwitcher: root.layouts.length > 1 && root.leftWanted("keyboardLayout")
            Layout.preferredWidth: showSwitcher ? (layoutRow.implicitWidth + 24) : 0
            visible: Layout.preferredWidth > 0
            clip: true
            colBackground: Theme.m3secondaryContainer
            colBackgroundHover: Theme.colSecondaryContainerHover
            colRipple: Theme.colSecondaryContainerActive
            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            contentItem: Item {
                RowLayout {
                    id: layoutRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "keyboard"
                        iconSize: 18
                        color: Theme.m3onSecondaryContainer
                        fill: 1
                    }
                    StyledText {
                        text: root.layoutCode(root.currentLayout)
                        font.weight: Font.Bold
                        font.pixelSize: Theme.pxSmall
                        color: Theme.m3onSecondaryContainer
                    }
                }
            }
            onClicked: {
                const p = layoutButton.mapToItem(root, layoutButton.width / 2, 0);
                layoutDialog.anchorX = p.x;
                sessionPicker.close();
                userPicker.close();
                layoutDialog.toggle();
            }
        }
    }

    readonly property var layouts: keyboard ? keyboard.layouts : []
    readonly property int currentLayout: keyboard ? keyboard.currentLayout : 0
    function layoutCode(index) {
        const layout = root.layouts[index];
        return layout ? String(layout.shortName || layout.longName || "").toUpperCase() : "";
    }

    function leftWanted(id) {
        return Theme.islandsLeft.includes(id) && Theme.islandShown(id);
    }
    // Re-append the items in the configured order: a RowLayout lays its children out
    // in child order. The same trick as LockSurface.applyIslandOrder().
    function applyLeftOrder() {
        const items = { battery: batteryButton, capsLock: capsLockPill, keyboardLayout: layoutButton };
        for (const id of Theme.islandsLeft) {
            const item = items[id];
            if (!item)
                continue;
            const parent = item.parent;
            item.parent = null;
            item.parent = parent;
        }
    }
    Connections {
        target: Theme
        function onIslandsLeftChanged() {
            root.applyLeftOrder();
        }
    }

    PickerDialog {
        id: layoutDialog
        objectName: "layoutDialog"
        property real anchorX: 0
        z: 10
        x: anchorX - width / 2
        y: leftIsland.y - height - 10
        entries: root.layouts.map((l, i) => ({ icon: "keyboard", label: root.layoutCode(i), active: i === root.currentLayout }))
        onPicked: index => {
            keyboard.currentLayout = index;
            root.forceFieldFocus();
        }
    }

    // ── bottom left, outermost: user and session ───────────────────────────
    // Same row and order as before the status island: session, user, status.
    MorphPicker {
        id: userPicker
        objectName: "userPicker"
        anchors {
            right: leftIsland.visible ? leftIsland.left : mainIsland.left
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        icon: "person"
        title: qsTr("Switch user")
        image: root.avatarFor(root.currentUser)
        label: root.displayName
        entries: {
            const list = [];
            for (let i = 0; i < users.count; i++) {
                const u = users.objectAt(i);
                if (u)
                    list.push({ icon: "person", image: root.avatarFor(u), label: u.realName || u.name, detail: u.realName && u.realName !== u.name ? u.name : "", active: i === root.userIndex });
            }
            return list;
        }
        onOpenChanged: if (open) { layoutDialog.close(); sessionPicker.close(); }
        onPicked: index => {
            if (index === root.userIndex)
                return;
            root.userIndex = index;
            root.failed = false;
            passwordBox.text = "";
        }
        onDismissed: root.forceFieldFocus()
    }

    MorphPicker {
        id: sessionPicker
        objectName: "sessionPicker"
        anchors {
            right: userPicker.left
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        visible: sessions.count > 0
        icon: "desktop_windows"
        title: qsTr("Session")
        label: root.sessionName
        entries: {
            const list = [];
            for (let i = 0; i < sessions.count; i++) {
                const s = sessions.objectAt(i);
                if (s)
                    list.push({ icon: "desktop_windows", label: s.name, detail: s.kind, active: i === root.sessionIndex });
            }
            return list;
        }
        onOpenChanged: if (open) { layoutDialog.close(); userPicker.close(); }
        onPicked: index => root.sessionIndex = index
        onDismissed: root.forceFieldFocus()
    }

    // ── bottom right: power ────────────────────────────────────────────────
    Toolbar {
        id: rightIsland
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        visible: rightRepeater.count > 0

        Repeater {
            id: rightRepeater
            model: Theme.islandsRight.filter(id => Theme.islandShown(id) && root.rightAvailable(id))
            delegate: IconIslandButton {
                required property string modelData
                iconName: root.rightIcon(modelData)
                tooltip: root.rightTooltip(modelData)
                onClicked: root.rightAction(modelData)
            }
        }
    }

    function rightAvailable(id) {
        switch (id) {
        case "sleep": return sddm.canSuspend;
        case "power": return sddm.canPowerOff;
        case "reboot": return sddm.canReboot;
        default: return false;
        }
    }
    function rightIcon(id) {
        return ({ sleep: "dark_mode", power: "power_settings_new", reboot: "restart_alt" })[id] ?? "";
    }
    function rightTooltip(id) {
        switch (id) {
        case "sleep": return qsTr("Sleep");
        case "power": return qsTr("Shutdown");
        case "reboot": return qsTr("Reboot");
        default: return "";
        }
    }
    function rightAction(id) {
        switch (id) {
        case "sleep": sddm.suspend(); break;
        case "power": sddm.powerOff(); break;
        case "reboot": sddm.reboot(); break;
        }
    }
}
