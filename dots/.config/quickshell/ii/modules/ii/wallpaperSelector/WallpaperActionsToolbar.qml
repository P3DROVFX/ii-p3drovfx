import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Toolbar {
    id: actionToolbar

    padding: 6
    spacing: 6
    colBackground: Appearance.m3colors.m3surfaceContainerLow

    component ActionButton: IconToolbarButton {
        implicitWidth: height

        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        colRipple: Appearance.colors.colLayer2Active
        colRippleToggled: Appearance.colors.colPrimaryActive
    }

    component ActionSlot: Item {
        id: actionSlot

        default property alias slotData: slot.data

        implicitWidth: Math.max(0, Appearance.sizes.toolbarHeight - actionToolbar.padding * 2)
        implicitHeight: 0
        clip: true
        opacity: 1
        enabled: true

        Layout.fillHeight: true
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth

        Item {
            id: slot
            anchors.fill: parent
        }
    }

    ActionSlot {
        ActionButton {
            id: openFileButton
            anchors.fill: parent

            onClicked: {
                Wallpapers.openFallbackPicker(wallpaperSelectorContent.useDarkMode);
                GlobalStates.wallpaperSelectorOpen = false;
            }
            altAction: () => {
                Wallpapers.openFallbackPicker(wallpaperSelectorContent.useDarkMode);
                GlobalStates.wallpaperSelectorOpen = false;
                Config.options.wallpaperSelector.useSystemFileDialog = true;
            }
            text: "open_in_new"

            StyledToolTip {
                text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
            }
        }
    }

    ActionSlot {
        ActionButton {
            id: randomButton
            anchors.fill: parent

            onClicked: {
                if (wallpaperSelectorContent.browserMode) {
                    if (wallpaperSelectorContent.apiImages.length > 0) {
                        const randomImg = wallpaperSelectorContent.apiImages[Math.floor(Math.random() * wallpaperSelectorContent.apiImages.length)];
                        wallpaperSelectorContent.selectWallpaperPath(randomImg.actualPath || randomImg.filePath);
                    }
                } else if (wallpaperSelectorContent.favMode) {
                    const favs = Persistent.states.wallpaper.favourites;
                    if (favs.length > 0) {
                        const randomPath = favs[Math.floor(Math.random() * favs.length)];
                        wallpaperSelectorContent.selectWallpaperPath(randomPath);
                    }
                } else {
                    Wallpapers.randomFromCurrentFolder();
                }
            }
            text: "ifl"

            StyledToolTip {
                text: Translation.tr("Pick random from this folder")
            }
        }
    }

    ActionSlot {
        ActionButton {
            id: refreshButton
            anchors.fill: parent

            onClicked: wallpaperSelectorContent.updateThumbnails(true)
            text: "refresh"

            StyledToolTip {
                text: wallpaperSelectorContent.thumbnailReloadSuggested
                    ? Translation.tr("Some thumbnails failed to load. Click Reload thumbnails to regenerate them.")
                    : Translation.tr("Reload thumbnails (for high resolution displays)")
                extraVisibleCondition: !wallpaperSelectorContent.thumbnailReloadSuggested
                alternativeVisibleCondition: wallpaperSelectorContent.thumbnailReloadSuggested
                requireOverlay: false
            }
        }
    }

    ActionSlot {
        ActionButton {
            id: colorFilterButton
            anchors.fill: parent

            toggled: wallpaperSelectorContent.colorFilterVisible
            onClicked: wallpaperSelectorContent.toggleColorFilter()
            text: "palette"

            StyledToolTip {
                text: wallpaperSelectorContent.colorCacheUpdating ? Translation.tr("Updating color cache...") : Translation.tr("Filter by color")
            }
        }
    }

}
