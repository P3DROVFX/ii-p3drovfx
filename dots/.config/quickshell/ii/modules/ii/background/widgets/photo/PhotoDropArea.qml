import QtQuick
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../../dock/utilities/UtilityFiles.js" as UtilityFiles

/**
 * Drop target for the photo widgets: drag an image out of a file manager (or
 * anything that offers a file:// text/uri-list) onto the widget and it becomes
 * the widget's picture.
 *
 * Place it over the widget's picture area. It only listens to the drag-and-drop
 * protocol, so mouse presses, widget dragging and the picker click underneath
 * are not affected.
 *
 * Where the picture goes (autoPersist):
 * - this widget's own entry (Config.updateWidgetImagePath) when `instanceId` is
 *   still on the desktop, so two instances of the same widget keep their own;
 * - else the widget type's shared `imagePath` (`entryName`).
 * Hosts that store the picture elsewhere (the quick toggle tile) turn
 * autoPersist off and handle `imageDropped` themselves.
 *
 * The overlay follows the widget's geometry through `shapeMode`:
 * "rectangle" (uses `radius`), "circle", or "materialShape" (uses `materialShape`).
 */
DropArea {
    id: root

    /** The widget's instance id (AbstractBackgroundWidget.widgetInstance.id). */
    property string instanceId: ""
    /** The widget type's config entry, the fallback destination. */
    property string entryName: ""
    property bool autoPersist: true

    property string shapeMode: "rectangle"
    property real radius: Appearance.rounding.windowRounding
    property var materialShape: MaterialShape.Shape.Cookie12Sided

    /** Emitted with the absolute path of the dropped image. */
    signal imageDropped(string path)

    /** True while an acceptable drag hovers the area. */
    readonly property bool dragOver: root.containsDrag

    keys: ["text/uri-list"]

    // Local images only: everything else is ignored rather than half-handled.
    function imagePaths(urls) {
        return UtilityFiles.dedupe(Array.from(urls ?? [])).filter(p => p.startsWith("/") && UtilityFiles.isImage(p));
    }

    function applyPath(path: string): void {
        if (path.length === 0)
            return;
        root.imageDropped(path);
        if (!root.autoPersist)
            return;
        if (root.instanceId !== "" && WidgetPlacement.findEntry(Config.options.background.activeWidgets, root.instanceId)) {
            Config.updateWidgetImagePath(root.instanceId, path);
            return;
        }
        const entry = Config.options.background.widgets[root.entryName];
        if (entry)
            entry.imagePath = path;
    }

    onEntered: drag => {
        // The URI list may not be readable yet while the drag is in flight: only
        // refuse when it is there and holds no image.
        const urls = Array.from(drag.urls ?? []);
        if (urls.length > 0 && root.imagePaths(urls).length === 0)
            drag.accepted = false;
    }

    onDropped: drop => {
        const paths = root.imagePaths(drop.urls);
        if (paths.length === 0) {
            drop.accepted = false;
            return;
        }
        // Copy, never move: the file manager must not delete the original.
        drop.accept(Qt.CopyAction);
        root.applyPath(paths[0]);
    }

    z: 10

    Item {
        id: overlay
        anchors.fill: parent
        opacity: root.dragOver ? 1 : 0
        scale: root.dragOver ? 1 : 0.94
        visible: opacity > 0.01
        enabled: false

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.reducedMotion ? 0 : 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.reducedMotion ? 0 : 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }

        readonly property color fillColor: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 0.12)
        readonly property color ringColor: Appearance.colors.colPrimary

        Rectangle {
            anchors.fill: parent
            visible: root.shapeMode !== "materialShape"
            radius: root.shapeMode === "circle" ? Math.min(width, height) / 2 : root.radius
            color: overlay.fillColor
            border.width: 2
            border.color: overlay.ringColor
        }

        MaterialShape {
            anchors.fill: parent
            visible: root.shapeMode === "materialShape"
            shape: root.materialShape
            color: overlay.fillColor
        }

        Rectangle {
            id: badge
            anchors.centerIn: parent
            width: Math.min(64, Math.max(32, Math.min(parent.width, parent.height) * 0.4))
            height: width
            radius: width / 2
            color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                text: "add_photo_alternate"
                iconSize: Math.round(badge.width * 0.58)
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
