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
        "nextLabelKey": "Continue",
        "nextIcon": "wifi",
        "component": "WelcomeStartPage.qml"
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
        "nextLabelKey": "Choose your experience",
        "nextIcon": "dashboard_customize",
        "component": "WelcomeDisplaysPage.qml"
    }, {
        "id": "experience",
        "titleKey": "Choose how II behaves",
        "subtitleKey": "Pick a shell mode and the bar placement that fits your workflow.",
        "icon": "dashboard_customize",
        "headerShape": MaterialShape.Shape.Sunny,
        "accentRole": "primary",
        "nextLabelKey": "Explore tutorials",
        "nextIcon": "school",
        "component": "WelcomeExperiencePage.qml"
    }, {
        "id": "learn",
        "titleKey": "Learn the useful features",
        "subtitleKey": "Set up only the integrations you plan to use.",
        "icon": "school",
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
