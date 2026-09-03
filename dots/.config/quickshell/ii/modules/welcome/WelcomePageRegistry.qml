pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Active Welcome setup pages. Page IDs are stable contracts; page order is
 * presentation metadata and must never be used as identity.
 *
 * `nextLabelKey` names the step the button leads to, not the action it
 * performs, so inserting a page means fixing the label of the one before it.
 */
QtObject {
    id: root

    readonly property var pages: [{
        "id": "hello",
        "titleKey": "Hi there",
        "subtitleKey": "Let's get your workspace ready.",
        "icon": "waving_hand",
        "headerShape": MaterialShape.Shape.PixelCircle,
        "accentRole": "primary",
        "nextLabelKey": "Let's go",
        "nextIcon": "arrow_forward",
        "component": "WelcomeHelloPage.qml"
    }, {
        "id": "language",
        "titleKey": "Choose your language",
        "subtitleKey": "You can change this later in Settings.",
        "icon": "language",
        "headerShape": MaterialShape.Shape.Circle,
        "accentRole": "secondary",
        "nextLabelKey": "Next",
        "nextIcon": "translate",
        "component": "WelcomeLanguagePage.qml"
    }, {
        "id": "keyboard",
        "titleKey": "Choose your keyboard layout",
        "subtitleKey": "Pick a layout for this computer.",
        "icon": "keyboard",
        "headerShape": MaterialShape.Shape.Circle,
        "accentRole": "tertiary",
        "nextLabelKey": "Next",
        "nextIcon": "keyboard",
        "component": "WelcomeKeyboardLayoutPage.qml"
    }, {
        "id": "time",
        "titleKey": "Set the date and time",
        "subtitleKey": "Choose the formats that feel natural to you.",
        "icon": "schedule",
        "headerShape": MaterialShape.Shape.SoftBurst,
        "accentRole": "primary",
        "nextLabelKey": "Get connected",
        "nextIcon": "schedule",
        "component": "WelcomeTimePage.qml"
    }, {
        "id": "start",
        "titleKey": "Get connected",
        "subtitleKey": "Connect the essentials before you start. You can change these later.",
        "icon": "wifi",
        "headerShape": MaterialShape.Shape.Cookie9Sided,
        "accentRole": "primary",
        "nextLabelKey": "Add your name",
        "nextIcon": "person",
        "component": "WelcomeStartPage.qml"
    }, {
        "id": "profile",
        "titleKey": "Add your name",
        "subtitleKey": "II greets you by name and signs your desktop with it.",
        "icon": "person",
        "headerShape": MaterialShape.Shape.Clover4Leaf,
        "accentRole": "secondary",
        "nextLabelKey": "Make it yours",
        "nextIcon": "palette",
        "component": "WelcomeProfilePage.qml"
    }, {
        "id": "personalize",
        "titleKey": "Make it yours",
        "subtitleKey": "Choose a wallpaper and a color scheme, or start from a ready-made look.",
        "icon": "palette",
        "headerShape": MaterialShape.Shape.SoftBurst,
        "accentRole": "secondary",
        "nextLabelKey": "Set up displays",
        "nextIcon": "desktop_windows",
        "component": "WelcomePersonalizePage.qml"
    }, {
        "id": "displays",
        "titleKey": "Set up your displays",
        "subtitleKey": "Arrange the screens you use every day.",
        "icon": "desktop_windows",
        "headerShape": MaterialShape.Shape.Cookie7Sided,
        "accentRole": "tertiary",
        "nextLabelKey": "Arrange your bar",
        "nextIcon": "edit",
        "component": "WelcomeDisplaysPage.qml"
    }, {
        "id": "bar",
        // The step does not ask questions of its own: it opens Edit Mode, and
        // the real bar answers them.
        "titleKey": "Arrange your bar",
        "subtitleKey": "Edit mode is open behind this window. Move things around, or skip it.",
        "icon": "edit",
        "headerShape": MaterialShape.Shape.Gem,
        "accentRole": "secondary",
        "nextLabelKey": "Learn the shortcuts",
        "nextIcon": "keyboard",
        "component": "WelcomeBarPage.qml"
    }, {
        "id": "shortcuts",
        "titleKey": "Shortcuts to remember",
        "subtitleKey": "A few keys to start with, and where every other one lives.",
        "icon": "keyboard",
        "headerShape": MaterialShape.Shape.PixelTriangle,
        "accentRole": "tertiary",
        "nextLabelKey": "Meet Search",
        "nextIcon": "search",
        "component": "WelcomeShortcutsPage.qml"
    }, {
        "id": "search",
        "titleKey": "One box for everything",
        "subtitleKey": "Search finds apps, files, windows and answers — and opens whole panels.",
        "icon": "search",
        "headerShape": MaterialShape.Shape.VerySunny,
        "accentRole": "primary",
        "nextLabelKey": "Connect your accounts",
        "nextIcon": "link",
        "component": "WelcomeSearchPage.qml"
    }, {
        "id": "learn",
        // Named for what it holds. It offers four account integrations, and
        // calling that "the useful features" both oversold it and took the
        // word the shortcuts and Search steps needed.
        "titleKey": "Connect your accounts",
        "subtitleKey": "Only the ones you already use. The rest can wait.",
        "icon": "link",
        "headerShape": MaterialShape.Shape.Flower,
        "accentRole": "tertiary",
        "nextLabelKey": "Finish setup",
        "nextIcon": "check",
        "component": "WelcomeLearnPage.qml"
    }, {
        "id": "finish",
        "titleKey": "All set!",
        "subtitleKey": "II is ready for you to use.",
        "icon": "check_circle",
        "headerShape": MaterialShape.Shape.SoftBurst,
        "accentRole": "primary",
        "nextLabelKey": "Start using II",
        "nextIcon": "arrow_forward",
        "component": "WelcomeFinishPage.qml"
    }]

    function pageIndexById(id: string): int {
        for (let i = 0; i < root.pages.length; i++) {
            if (root.pages[i].id === id)
                return i;
        }
        return -1;
    }

    function pageById(id: string): var {
        const index = root.pageIndexById(id);
        return index >= 0 ? root.pages[index] : null;
    }

    function titleFor(id: string): string {
        const page = root.pageById(id);
        return page ? Translation.tr(page.titleKey) : "";
    }

    function subtitleFor(id: string): string {
        const page = root.pageById(id);
        return page ? Translation.tr(page.subtitleKey) : "";
    }

    function headerShapeFor(id: string): var {
        const page = root.pageById(id);
        return page ? page.headerShape : MaterialShape.Shape.Cookie9Sided;
    }

    function nextLabelFor(id: string): string {
        const page = root.pageById(id);
        return page ? Translation.tr(page.nextLabelKey) : Translation.tr("Continue");
    }

    function nextIconFor(id: string): string {
        const page = root.pageById(id);
        return page ? page.nextIcon : "arrow_forward";
    }
}
