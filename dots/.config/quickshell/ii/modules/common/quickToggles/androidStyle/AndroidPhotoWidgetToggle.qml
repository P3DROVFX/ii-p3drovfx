pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Freeform Photo Widget Quick Toggle for Dynamic Island dashboard.
 *
 * Requirements:
 * - Totally freeform sizing with full image fill (Image.PreserveAspectCrop).
 * - Clipped with smooth corner radius matching the tile surface (root.surfaceRadius).
 * - No internal design or text chrome: only the image filling the toggle.
 * - Clicking the image outside edit mode opens the user's system file picker (zenity / kdialog).
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Photo")

    clipContent: true

    readonly property string tileId: root.buttonData?.id ?? "photoWidget"
    property string chosenPath: ""

    readonly property string customPath: {
        if (root.chosenPath !== "")
            return root.chosenPath;
        if (root.buttonData && root.buttonData.imagePath && root.buttonData.imagePath !== "")
            return root.buttonData.imagePath;
        const imagesMap = Config.options?.dynamicIsland?.dashboard?.photoWidgetImages;
        if (imagesMap && imagesMap[root.tileId] && imagesMap[root.tileId] !== "")
            return imagesMap[root.tileId];
        return Config.options?.dynamicIsland?.dashboard?.photoWidgetPath ?? "";
    }

    readonly property string imageSource: {
        if (!root.customPath || root.customPath === "")
            return "";
        let p = root.customPath;
        const qIdx = p.indexOf("?");
        if (qIdx !== -1) p = p.substring(0, qIdx);
        return p.startsWith("file://") ? p : ("file://" + p);
    }

    readonly property bool hasImage: root.imageSource !== ""

    readonly property bool isAnimated: {
        const lower = root.imageSource.toLowerCase();
        return lower.includes(".gif") || lower.includes(".webp");
    }

    function openPicker(): void {
        WidgetPhotoPicker.pickWithCallback((path) => {
            if (!path || path.length === 0)
                return;
            root.chosenPath = path;

            // 1. Update buttonData
            if (root.buttonData)
                root.buttonData.imagePath = path;

            // 2. Persist to Config dashboard photoWidgetPath
            if (Config.options?.dynamicIsland?.dashboard) {
                Config.options.dynamicIsland.dashboard.photoWidgetPath = path;

                // 3. Update the tile inside dynamicIsland.dashboard.quickToggles.pages
                const qt = Config.options.dynamicIsland.dashboard.quickToggles;
                if (qt && qt.pages) {
                    try {
                        let updatedPages = JSON.parse(JSON.stringify(qt.pages));
                        let found = false;
                        for (let p = 0; p < updatedPages.length; p++) {
                            let page = updatedPages[p];
                            for (let i = 0; i < page.length; i++) {
                                if (page[i] && (page[i].id === root.tileId || page[i].type === "photoWidget")) {
                                    page[i].imagePath = path;
                                    found = true;
                                    break;
                                }
                            }
                            if (found) break;
                        }
                        if (found) {
                            qt.pages = updatedPages;
                        }
                    } catch (e) {
                        console.warn("[PhotoWidget] Failed to update tile in pages:", e);
                    }
                }
            }

            // 4. Force save options to disk so it persists across restarts
            if (typeof Config.saveOptionsNow === "function") {
                Config.saveOptionsNow();
            }
        });
    }

    // ── IMAGE FILL CONTENT WITH ROUNDED CORNER MASK ─────────────────────────

    Item {
        id: imageContainer
        anchors.fill: parent
        layer.enabled: root.hasImage
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: imageContainer.width
                height: imageContainer.height
                radius: root.surfaceRadius
            }
        }

        // Static Image loader
        Image {
            id: staticImg
            anchors.fill: parent
            source: (!root.hasImage || root.isAnimated) ? "" : root.imageSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            retainWhileLoading: true
            visible: root.hasImage && !root.isAnimated
            smooth: true
            mipmap: true
        }

        // Animated GIF / WebP loader
        AnimatedImage {
            id: animImg
            anchors.fill: parent
            source: (root.hasImage && root.isAnimated) ? root.imageSource : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            playing: !root.isUnused && root.visible
            paused: root.isUnused || !root.visible
            visible: root.hasImage && root.isAnimated
        }
    }

    // Minimal placeholder when no photo has been chosen yet
    Item {
        anchors.fill: parent
        visible: !root.hasImage

        Column {
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "add_photo_alternate"
                iconSize: Math.max(24, Math.min(root.surface.width, root.surface.height) * 0.35)
                color: Appearance.colors.colOnLayer2
                opacity: 0.45
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Translation.tr("Select image")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer3
                visible: root.surface.height >= 80
            }
        }
    }

    // Interactive picker trigger when outside edit mode
    MouseArea {
        anchors.fill: parent
        z: 2
        enabled: !root.editMode
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openPicker()
    }
}
