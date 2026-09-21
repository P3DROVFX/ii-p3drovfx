import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Toolbar {
    id: extraOptions
    z: 20
    padding: 6
    spacing: 6
    colBackground: Appearance.m3colors.m3surfaceContainerLow

    property string text: filterField.text
    property alias searchField: filterField
    signal closeRequested

    function focusSearch() {
        filterField.forceActiveFocus();
        filterField.cursorPosition = filterField.text.length;
    }

    function setSearchText(value) {
        filterField.text = value;
        filterField.cursorPosition = filterField.text.length;
    }

    function clearSearch() {
        setSearchText("");
    }

    ToolbarTextField {
        id: filterField
        implicitWidth: Appearance.sizes.wallpaperSelectorSearchWidth
        colBackground: Appearance.colors.colLayer2
        placeholderText: {
            if (wallpaperSelectorContent.browserMode) return Translation.tr("Search API (e.g. nature, city)");
            return focus ? Translation.tr("Search wallpapers") : Translation.tr("Hit \"/\" to search")
        }

        // Style
        clip: true
        font.pixelSize: Appearance.font.pixelSize.small

        // Search
        onTextChanged: {
            if (!wallpaperSelectorContent.browserMode) {
                Wallpapers.searchQuery = text;
                if (wallpaperSelectorContent.favMode) {
                    wallpaperSelectorContent.refreshFavourites();
                }
            }
        }

        // The floating pill only owns the keyboard when it is on screen: the
        // compact layout keeps this toolbar hidden and draws its own search in the
        // address row, which would otherwise lose the focus to this invisible field.
        Component.onCompleted: if (extraOptions.visible) extraOptions.focusSearch()

        onAccepted: {
            if (wallpaperSelectorContent.browserMode && text.trim().length > 0) {
                const newTags = text.trim().split(/\s+/);
                const allTags = [...newTags];
                wallpaperSelectorContent.moreOptionsModelData = null
                WallpaperBrowser.clearResponses();
                WallpaperBrowser.makeRequest(allTags, 20, 1);
                wallpaperSelectorContent.view.currentIndex = 0;
                text = "";
            } else if (!wallpaperSelectorContent.browserMode && wallpaperSelectorContent.view.count > 0) {
                // TextInput owns the focus while searching, so forward Enter
                // explicitly to the same activation path used by the shell.
                wallpaperSelectorContent.view.activateCurrent();
            }
        }

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
                wallpaperSelectorContent.handleFilePasting(event);
                return;
            }
            else if (text.length !== 0) {
                // No filtering, just navigate grid
                if (event.key === Qt.Key_Down) {
                    wallpaperSelectorContent.view.moveSelection(wallpaperSelectorContent.compact ? 1 : grid.columns);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up) {
                    wallpaperSelectorContent.view.moveSelection(wallpaperSelectorContent.compact ? -1 : -grid.columns);
                    event.accepted = true;
                    return;
                }
            }
            event.accepted = false;
        }
    }

    IconToolbarButton {
        implicitWidth: height
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
        colText: Appearance.colors.colOnLayer2
        colRipple: Appearance.colors.colLayer2Active
        colRippleToggled: Appearance.colors.colPrimaryActive
        downAction: () => extraOptions.closeRequested()
        onClicked: extraOptions.closeRequested()
        text: "close"
        StyledToolTip {
            text: Translation.tr("Cancel wallpaper selection")
        }
    }                        
}
